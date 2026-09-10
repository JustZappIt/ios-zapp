// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// The verification list, and the run one row starts.
///
/// Everything the list shows is read on chain: which accounts are already verified, and what each
/// one is worth. That table is today's configuration, not a constant, and a wrong number here is a
/// promise about money.
@Reducer
struct IncreaseReputation {
    @ObservableState
    struct State: Equatable {
        enum Stage: Equatable {
            case preparing
            case ready
            case verifying
            case submitting
            case done
            case failed
        }

        struct Run: Equatable {
            let platformID: String
            /// The brand's own spelling. A cold-start resume opens before the list has loaded, so
            /// it starts as the routing key and is corrected the moment the read lands.
            var name: String
            var stage: Stage
            /// Where the Verifier lives for this session. Nil until Reclaim has minted one.
            var launchURL: String?
            var errorMessage: String?
            /// Set only at `.done`: what the chain says now, not what we predicted.
            var newPoints: String?
            var newBuyLimitMicros: String?
        }

        var currencyCode: String
        var isLoading = true
        var platforms: [ReputationPlatformModel] = []
        /// Non-nil once a row is tapped: the run takes over the body, in place, with no new route.
        var run: Run?
        var errorMessage: String?
        var isInfoPresented = false
        /// So a failure marks the step it failed *on* rather than the first one.
        var lastActiveStage: Stage = .ready
        /// Carried by the return link on a cold start, and consumed exactly once.
        var resumeSessionID: String?
        var resumePlatformID: String?

        var isRunLive: Bool {
            guard let run else { return false }
            return run.stage != .done && run.stage != .failed
        }

        var canRetryLoad: Bool { errorMessage != nil && run == nil }

        var steps: [ZappOfframpStepItem] {
            IncreaseReputation.steps(stage: run?.stage, lastActiveStage: lastActiveStage)
        }

        static func initial(
            currencyCode: String,
            resumeSessionID: String? = nil,
            resumePlatformID: String? = nil
        ) -> State {
            State(
                currencyCode: currencyCode,
                resumeSessionID: resumeSessionID,
                resumePlatformID: resumePlatformID
            )
        }
    }

    enum Action: Equatable {
        case onAppear
        case summaryLoaded(ReputationSummaryModel)
        case loadFailed
        case retryLoadTapped
        case platformTapped(String)
        case statusReceived(ReclaimStatusModel)
        case runEnded
        case verifierOpened(platformID: String, accepted: Bool)
        case cancelRunTapped
        case dismissRunTapped
        case doneTapped
        case infoTapped
        case infoDismissed
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
        }
    }

    @Dependency(\.reputation) var reputation

    private enum CancelID {
        case load
        case run
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                var effects: [Effect<Action>] = [load(state)]
                if let sessionID = state.resumeSessionID, let platformID = state.resumePlatformID {
                    state.resumeSessionID = nil
                    state.resumePlatformID = nil
                    effects.append(startRun(&state, platformID: platformID, sessionID: sessionID))
                }
                return .merge(effects)

            case .retryLoadTapped:
                return load(state)

            case let .summaryLoaded(summary):
                state.isLoading = false
                state.errorMessage = nil
                state.platforms = visiblePlatforms(summary, currencyCode: state.currencyCode)
                if let name = summary.platforms.first(where: { $0.id == state.run?.platformID })?.name {
                    state.run?.name = name
                }
                return .none

            case .loadFailed:
                state.isLoading = false
                state.errorMessage = String(localizable: .reputationUnreadableBody)
                return .none

            case let .platformTapped(platformID):
                // A second tap while a run is live would mint a session over the one the user
                // is already proving against, and only the second is polled.
                guard state.run == nil,
                      let platform = state.platforms.first(where: { $0.id == platformID }),
                      !platform.isVerified else { return .none }
                return startRun(&state, platformID: platformID, sessionID: nil)

            case let .statusReceived(status):
                apply(status, to: &state)
                return .none

            case .runEnded:
                // The stream can end without a terminal status when the session is torn down.
                // Leaving the run mid-stage would strand the screen on a spinner.
                guard state.isRunLive else { return .none }
                state.run?.stage = .failed
                state.run?.errorMessage = ReputationCopy.failureMessage(.network)
                return .none

            case let .verifierOpened(platformID, accepted):
                // ☠ Only a *successful* open stops the re-minting, and only for the run that is
                // still on screen. A refused open leaves the session being refreshed, which is
                // what the next tap needs; a callback outliving its own run would mark the run
                // after it as opened before the user has left, and that one's link then ages out
                // unwatched.
                guard accepted, state.run?.platformID == platformID else { return .none }
                return .run { _ in await reputation.markVerifierOpened() }

            case .cancelRunTapped, .dismissRunTapped:
                // Cancelling leaves the Reclaim session to expire on its own. It is never
                // surfaced later as an error — the user chose to stop. Cancelling the effect is
                // the whole teardown: it unwinds the Kotlin collection, which frees the run lock
                // and forgets the launch signal.
                state.run = nil
                state.lastActiveStage = .ready
                return .cancel(id: CancelID.run)

            case .doneTapped:
                return .send(.delegate(.close))

            case .infoTapped:
                state.isInfoPresented = true
                return .none

            case .infoDismissed:
                state.isInfoPresented = false
                return .none

            case .backTapped:
                // Back closes the run first, exactly as Android does: the run took the body over
                // in place, so it is what the user means by back.
                if state.run != nil { return .send(.dismissRunTapped) }
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.run),
                    .send(.delegate(.close))
                )

            case .delegate:
                return .none
            }
        }
    }

    private func load(_ state: State) -> Effect<Action> {
        let currencyCode = state.currencyCode
        return .run { send in
            await send(.summaryLoaded(try await reputation.summary(currencyCode: currencyCode)))
        } catch: { _, send in
            await send(.loadFailed)
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// `sessionID` non-nil resumes the session the return link named; nil mints a fresh one.
    ///
    /// A resume opens at `verifying`, and counts opening the Verifier as done: the user has
    /// already been and come back, so a failure here must not mark the step they clearly completed.
    private func startRun(_ state: inout State, platformID: String, sessionID: String?) -> Effect<Action> {
        state.lastActiveStage = sessionID == nil ? .ready : .verifying
        state.run = State.Run(
            platformID: platformID,
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
                    sessionID: sessionID
                )
            } else {
                statuses = try await reputation.verify(platformID: platformID, currencyCode: currencyCode)
            }
            for try await status in statuses {
                await send(.statusReceived(status))
            }
            await send(.runEnded)
        } catch: { _, send in
            await send(.statusReceived(.failed(.network)))
        }
        .cancellable(id: CancelID.run, cancelInFlight: true)
    }

    private func apply(_ status: ReclaimStatusModel, to state: inout State) {
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
            state.run?.stage = .done
            state.run?.newPoints = summary.points
            state.run?.newBuyLimitMicros = summary.buyLimitMicros
            state.platforms = visiblePlatforms(summary, currencyCode: state.currencyCode)
        case let .failed(failure):
            state.run?.stage = .failed
            state.run?.errorMessage = ReputationCopy.failureMessage(failure)
        }
    }

    /// p2p.me's own client hides Binance in India, so an INR user who tried it would meet a
    /// failure we could have predicted. The corridor is the country signal we actually have — the
    /// user is buying with rupees — and it beats a device locale, which says where the phone was
    /// set up. The facade returns every platform; the rule belongs beside the currency it depends on.
    private func visiblePlatforms(
        _ summary: ReputationSummaryModel,
        currencyCode: String
    ) -> [ReputationPlatformModel] {
        guard currencyCode.caseInsensitiveCompare(ReputationCorridor.inr) == .orderedSame else {
            return summary.platforms
        }
        return summary.platforms.filter { $0.id != SocialPlatformID.binance }
    }

    /// The first active indicator starts only once the user has left Zapp to begin verification.
    static func steps(stage: State.Stage?, lastActiveStage: State.Stage) -> [ZappOfframpStepItem] {
        let order: [State.Stage] = [.ready, .verifying, .submitting]
        let labels = [
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
