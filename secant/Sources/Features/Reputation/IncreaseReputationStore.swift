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
            enum Kind: Equatable {
                case social(platformID: String)
                case selfie
            }

            let id: UUID
            let kind: Kind
            /// The brand's own spelling. A cold-start resume opens before the list has loaded, so
            /// it starts as the routing key and is corrected the moment the read lands.
            var name: String
            var stage: Stage
            /// Where the Verifier, or the selfie widget, lives for this session. Nil until minted.
            var launchURL: String?
            var errorMessage: String?
            /// Set only at `.done`: what the chain says now, not what we predicted.
            var newPoints: String?
            var newBuyLimitMicros: String?
            /// Selfie runs only; set by the tap, not by the driver.
            var isWidgetOpened = false

            var platformID: String? {
                guard case let .social(platformID) = kind else { return nil }
                return platformID
            }

            var isSelfie: Bool { kind == .selfie }

            var isAwaitingReturn: Bool { isSelfie && (stage == .ready || stage == .verifying) }
        }

        var currencyCode: String
        var isLoading = true
        var platforms: [ReputationPlatformModel] = []
        /// Nil where no integrator is deployed; the row does not render.
        var liveness: LivenessStandingModel?
        /// Non-nil once a row is tapped: the run takes over the body, in place, with no new route.
        var run: Run?
        var errorMessage: String?
        var isInfoPresented = false
        /// So a failure marks the step it failed *on* rather than the first one.
        var lastActiveStage: Stage = .ready
        /// External routing hints. They cannot start a write until the user confirms the resume.
        var resumeSessionID: String?
        var resumePlatformID: String?
        /// A widget redirect that arrived with no screen mounted; consumed on the first appearance.
        var resumeLivenessReturn: LivenessReturnModel?
        /// A completed write supersedes any summary read started before it.
        var summaryRevision = 0

        var requiresResumeConfirmation: Bool { resumeSessionID != nil && resumePlatformID != nil }

        var isRunLive: Bool {
            guard let run else { return false }
            return run.stage != .done && run.stage != .failed
        }

        var canRetryLoad: Bool { errorMessage != nil && run == nil }

        var steps: [ZappOfframpStepItem] {
            IncreaseReputation.steps(stage: run?.stage, lastActiveStage: lastActiveStage, isSelfie: run?.isSelfie == true)
        }

        static func initial(
            currencyCode: String,
            resumeSessionID: String? = nil,
            resumePlatformID: String? = nil,
            resumeLivenessReturn: LivenessReturnModel? = nil
        ) -> State {
            State(
                currencyCode: currencyCode,
                resumeSessionID: resumeSessionID,
                resumePlatformID: resumePlatformID,
                resumeLivenessReturn: resumeLivenessReturn
            )
        }
    }

    enum Action: Equatable {
        case onAppear
        case summaryLoaded(ReputationSummaryModel, revision: Int)
        case loadFailed(revision: Int)
        case retryLoadTapped
        case platformTapped(String)
        case selfieTapped
        case statusReceived(runID: UUID, status: ReclaimStatusModel)
        case livenessStatusReceived(runID: UUID, status: LivenessStatusModel)
        case livenessReturnReceived(LivenessReturnModel)
        case runEnded(runID: UUID)
        case verifierOpened(runID: UUID, accepted: Bool)
        case resumeConfirmed
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
    @Dependency(\.liveness) var liveness
    @Dependency(\.uuid) var uuid

    enum CancelID {
        case load
        case run
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Cleared whether or not a run can take it: a return left here would replay a spent code.
                let ret = state.resumeLivenessReturn
                state.resumeLivenessReturn = nil
                if let ret, state.run == nil {
                    return .merge(load(state), startSelfieResume(&state, ret))
                }
                return load(state)

            case .resumeConfirmed:
                // The URL alone is not consent: anyone can mint a session whose context names
                // this wallet. Only this explicit action permits polling and submitting its proof.
                guard state.run == nil,
                      let sessionID = state.resumeSessionID, let platformID = state.resumePlatformID else { return .none }
                state.resumeSessionID = nil
                state.resumePlatformID = nil
                return startRun(&state, platformID: platformID, sessionID: sessionID)

            case .retryLoadTapped:
                state.isLoading = true
                state.errorMessage = nil
                return load(state)

            case let .summaryLoaded(summary, revision):
                guard revision == state.summaryRevision else { return .none }
                state.isLoading = false
                state.errorMessage = nil
                state.platforms = visiblePlatforms(summary, currencyCode: state.currencyCode)
                state.liveness = summary.liveness
                if let name = summary.platforms.first(where: { $0.id == state.run?.platformID })?.name {
                    state.run?.name = name
                }
                return .none

            case let .loadFailed(revision):
                guard revision == state.summaryRevision else { return .none }
                state.isLoading = false
                state.errorMessage = String(localizable: .reputationUnreadableBody)
                return .none

            case let .platformTapped(platformID):
                // A second tap while a run is live would mint a session over the one the user
                // is already proving against, and only the second is polled.
                guard state.run == nil, !state.requiresResumeConfirmation,
                      let platform = state.platforms.first(where: { $0.id == platformID }),
                      !platform.isVerified else { return .none }
                return startRun(&state, platformID: platformID, sessionID: nil)

            case .selfieTapped:
                guard state.run == nil, !state.requiresResumeConfirmation,
                      let liveness = state.liveness, !liveness.isVerified else { return .none }
                return startSelfieRun(&state)

            case let .statusReceived(runID, status):
                guard state.run?.id == runID else { return .none }
                apply(status, to: &state)
                if case .done = status { return .cancel(id: CancelID.load) }
                return .none

            case let .livenessStatusReceived(runID, status):
                guard state.run?.id == runID else { return .none }
                apply(status, to: &state)
                if case .done = status { return .cancel(id: CancelID.load) }
                return .none

            case let .livenessReturnReceived(ret):
                if let run = state.run, run.isAwaitingReturn {
                    // Fire and forget: the run's own stream reports what the code was worth.
                    return .run { _ in _ = try await liveness.deliverReturn(ret) } catch: { _, _ in }
                }
                guard state.run == nil, !state.requiresResumeConfirmation else { return .none }
                return startSelfieResume(&state, ret)

            case let .runEnded(runID):
                // The stream can end without a terminal status when the session is torn down.
                // Leaving the run mid-stage would strand the screen on a spinner.
                guard state.run?.id == runID, state.isRunLive else { return .none }
                state.run?.stage = .failed
                state.run?.errorMessage = ReputationCopy.failureMessage(.network)
                return .none

            case let .verifierOpened(runID, accepted):
                // ☠ Only a *successful* open stops the re-minting, and only for the run that is
                // still on screen. A refused open leaves the session being refreshed, which is
                // what the next tap needs; a callback outliving its own run would mark the run
                // after it as opened before the user has left, and that one's link then ages out
                // unwatched.
                guard accepted, let run = state.run, run.id == runID, run.stage == .ready else { return .none }
                switch run.kind {
                case .social:
                    return .run { _ in await reputation.markVerifierOpened(runID: runID) }
                case .selfie:
                    state.run?.isWidgetOpened = true
                    state.run?.stage = .verifying
                    state.lastActiveStage = .verifying
                    return .none
                }

            case .cancelRunTapped, .dismissRunTapped:
                // Cancelling leaves the Reclaim session, or the widget session, to expire on its
                // own. It is never surfaced later as an error — the user chose to stop.
                // Cancelling the effect is the whole teardown: it unwinds the Kotlin collection,
                // which frees the run lock and forgets the launch or return signal.
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
                state.resumeSessionID = nil
                state.resumePlatformID = nil
                state.resumeLivenessReturn = nil
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
}
