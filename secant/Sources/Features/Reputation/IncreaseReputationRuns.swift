// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension IncreaseReputation {
    func load(_ state: State) -> Effect<Action> {
        let currencyCode = state.currencyCode
        let revision = state.summaryRevision
        return .run { send in
            await send(.summaryLoaded(try await reputation.summary(currencyCode: currencyCode), revision: revision))
        } catch: { _, send in
            await send(.loadFailed(revision: revision))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// `sessionID` non-nil resumes the session the return link named; nil mints a fresh one.
    ///
    /// A resume opens at `verifying`, and counts opening the Verifier as done: the user has
    /// already been and come back, so a failure here must not mark the step they clearly completed.
    func startRun(_ state: inout State, platformID: String, sessionID: String?) -> Effect<Action> {
        let runID = uuid()
        state.lastActiveStage = sessionID == nil ? .ready : .verifying
        state.run = State.Run(
            id: runID,
            kind: .social(platformID: platformID),
            name: state.platforms.first { $0.id == platformID }?.name ?? platformID,
            stage: sessionID == nil ? .preparing : .verifying
        )
        let currencyCode = state.currencyCode
        return .run { send in
            let statuses: ReclaimStatusStream
            if let sessionID {
                statuses = try await reputation.resume(
                    platformID: platformID,
                    currencyCode: currencyCode,
                    sessionID: sessionID,
                    runID: runID
                )
            } else {
                statuses = try await reputation.verify(platformID: platformID, currencyCode: currencyCode, runID: runID)
            }
            for try await status in statuses {
                await send(.statusReceived(runID: runID, status: status))
            }
            await send(.runEnded(runID: runID))
        } catch: { _, send in
            await send(.statusReceived(runID: runID, status: .failed(.network)))
        }
        .cancellable(id: CancelID.run, cancelInFlight: true)
    }

    func startSelfieRun(_ state: inout State) -> Effect<Action> {
        let runID = uuid()
        let nonce = uuid().uuidString.lowercased()
        state.lastActiveStage = .ready
        state.run = State.Run(id: runID, kind: .selfie, name: String(localizable: .increaseReputationLivenessRow), stage: .preparing)
        let currencyCode = state.currencyCode
        return collectSelfie(runID: runID) { try await liveness.verify(currencyCode: currencyCode, nonce: nonce, runID: runID) }
    }

    /// Opens at `verifying` with the widget counted as opened: the user has already been and come back.
    func startSelfieResume(_ state: inout State, _ ret: LivenessReturnModel) -> Effect<Action> {
        let runID = uuid()
        state.lastActiveStage = .verifying
        state.run = State.Run(
            id: runID,
            kind: .selfie,
            name: String(localizable: .increaseReputationLivenessRow),
            stage: .verifying,
            isWidgetOpened: true
        )
        return collectSelfie(runID: runID) { try await liveness.resume(ret: ret, runID: runID) }
    }

    func collectSelfie(
        runID: UUID,
        _ statuses: @escaping @Sendable () async throws -> LivenessStatusStream
    ) -> Effect<Action> {
        .run { send in
            for try await status in try await statuses() {
                await send(.livenessStatusReceived(runID: runID, status: status))
            }
            await send(.runEnded(runID: runID))
        } catch: { _, send in
            await send(.livenessStatusReceived(runID: runID, status: .failed(.network)))
        }
        .cancellable(id: CancelID.run, cancelInFlight: true)
    }

    func apply(_ status: ReclaimStatusModel, to state: inout State) {
        guard state.run != nil else { return }
        switch status {
        case .preparing:
            state.run?.stage = .preparing
        case let .ready(requestURL):
            state.run?.stage = .ready
            state.run?.launchURL = requestURL
            state.lastActiveStage = .ready
        case .verifying:
            state.run?.stage = .verifying
            state.lastActiveStage = .verifying
        case .submitting:
            state.run?.stage = .submitting
            state.lastActiveStage = .submitting
        case let .done(summary):
            state.summaryRevision += 1
            state.isLoading = false
            state.errorMessage = nil
            state.run?.stage = .done
            state.run?.newPoints = summary.points
            state.run?.newBuyLimitMicros = summary.buyLimitMicros
            state.platforms = visiblePlatforms(summary, currencyCode: state.currencyCode)
        case let .failed(failure):
            state.run?.stage = .failed
            state.run?.errorMessage = ReputationCopy.failureMessage(failure)
        }
    }

    func apply(_ status: LivenessStatusModel, to state: inout State) {
        guard let run = state.run else { return }
        switch status {
        case .preparing:
            state.run?.stage = .preparing
        case let .ready(widgetURL, _):
            state.run?.stage = .ready
            state.run?.launchURL = widgetURL
            state.lastActiveStage = .ready
        case .verifying:
            // The driver reports verifying as soon as the session exists; the screen follows the tap.
            guard run.isWidgetOpened else { return }
            state.run?.stage = .verifying
            state.lastActiveStage = .verifying
        case .submitting:
            state.run?.stage = .submitting
            state.lastActiveStage = .submitting
        case let .done(standing):
            state.summaryRevision += 1
            state.isLoading = false
            state.errorMessage = nil
            state.run?.stage = .done
            state.run?.newBuyLimitMicros = standing.limitMicros
            state.liveness = standing
        case .failed(.cancelled):
            // The user backed out of the widget: not an error to show.
            state.run = nil
            state.lastActiveStage = .ready
        case let .failed(failure):
            state.run?.stage = .failed
            state.run?.errorMessage = ReputationCopy.livenessFailureMessage(failure)
        }
    }

    /// p2p.me's own client hides Binance in India, so an INR user who tried it would meet a
    /// failure we could have predicted. The corridor is the country signal we actually have — the
    /// user is buying with rupees — and it beats a device locale, which says where the phone was
    /// set up. The facade returns every platform; the rule belongs beside the currency it depends on.
    func visiblePlatforms(
        _ summary: ReputationSummaryModel,
        currencyCode: String
    ) -> [ReputationPlatformModel] {
        guard currencyCode.caseInsensitiveCompare(ReputationCorridor.inr) == .orderedSame else {
            return summary.platforms
        }
        return summary.platforms.filter { $0.id != SocialPlatformID.binance }
    }

    /// The first active indicator starts only once the user has left Zapp to begin verification.
    static func steps(stage: State.Stage?, lastActiveStage: State.Stage, isSelfie: Bool = false) -> [ZappOfframpStepItem] {
        let order: [State.Stage] = [.ready, .verifying, .submitting]
        let labels = isSelfie
            ? [
                String(localizable: .increaseReputationLivenessStepOpen),
                String(localizable: .increaseReputationLivenessStepSelfie),
                String(localizable: .increaseReputationStepSave)
            ]
            : [
                String(localizable: .increaseReputationStepOpen),
                String(localizable: .increaseReputationStepProve),
                String(localizable: .increaseReputationStepSave)
            ]
        let reached: Int
        switch stage {
        case .preparing, .ready, nil: reached = -1
        case .done: reached = order.count
        case .failed: reached = order.firstIndex(of: lastActiveStage) ?? -1
        case let .some(active): reached = order.firstIndex(of: active) ?? -1
        }
        return labels.enumerated().map { index, label in
            let status: ZappOfframpStepStatus
            if stage == .failed && index == reached {
                status = .failed
            } else if index < reached {
                status = .completed
            } else if index == reached {
                status = .inProgress
            } else {
                status = .pending
            }
            return ZappOfframpStepItem(id: label, label: label, detail: nil, status: status)
        }
    }
}
