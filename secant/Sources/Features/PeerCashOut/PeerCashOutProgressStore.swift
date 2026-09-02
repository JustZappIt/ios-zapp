// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// Watches one cash-out. It does not own it: the attempt runs on an app-lifetime actor, so leaving
/// this screen stops the watching and nothing else, and coming back re-attaches to the same attempt
/// rather than starting another.
@Reducer
struct PeerCashOutProgress {
    @ObservableState
    struct State: Equatable {
        let attemptID: String

        var run: PeerRun?
        var transactionURL: URL?
        var startupErrorMessage: String?
        /// A retry is admitted against the balance like any other spend, so it can be refused. The
        /// attempt's own failure is still on screen, so the refusal needs a line of its own.
        var retryErrorMessage: String?
        var isLoading = true
        /// Cancellation does not guarantee a foreign async call stops. Results are accepted only
        /// while they belong to the currently visible subscription.
        var observationGeneration = 0

        var latest: PeerProgress? { run?.latest }
        var failure: PeerFailure? { run?.failure }
        var depositID: String? { run?.depositID }
        var isOrderLive: Bool { latest?.kind == .orderLive }

        var steps: [ZappOfframpStepItem] { PeerProgressSteps.build(from: run) }

        var title: String {
            if failure != nil || startupErrorMessage != nil {
                return String(localizable: .peerProgressTitleFailed)
            }
            guard let order = latest?.order else { return String(localizable: .peerProgressTitleSetup) }
            return order.buyerLegs.contains(where: \.holdsFunds)
                ? String(localizable: .peerProgressTitleBuyerPaying)
                : String(localizable: .peerProgressTitleLive)
        }

        var subtitle: String? {
            switch latest?.kind {
            case .creatingDeposit: return String(localizable: .peerProgressSubtitleCreating)
            case .orderLive: return String(localizable: .peerProgressSubtitleLive)
            default: return nil
            }
        }

        /// The three unknown-outcome codes deliberately offer nothing to press: a second attempt is
        /// how one deposit becomes two.
        var offersRetry: Bool { failure?.allowsManualRetry == true }

        var summaryRows: [ZappCompactLedgerRow] {
            guard let run else { return [] }
            return [
                ZappCompactLedgerRow(
                    label: String(localizable: .peerProgressSummaryAmount),
                    value: String(localizable: .peerUsdcAmount(run.amount.display))
                ),
                ZappCompactLedgerRow(
                    label: String(localizable: .peerProgressSummaryPaidTo),
                    value: PeerDestination.displayName(for: run.destinationCode)
                ),
                ZappCompactLedgerRow(
                    label: String(localizable: .peerProgressSummaryCurrencies),
                    value: run.currencyCodes.joined(separator: " · ")
                )
            ]
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case runnerStateChanged(PeerRunnerState, generation: Int)
        case startupFailed(String, generation: Int)
        case transactionURLResolved(URL?, generation: Int)
        case retryTapped
        case retryFailed(String, generation: Int)
        case viewOrderTapped
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
            case openOrder(depositID: String)
        }
    }

    @Dependency(\.peerCashOut) var peerCashOut

    private enum CancelID {
        case runner
        case transactionURL
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.observationGeneration &+= 1
                state.startupErrorMessage = nil
                state.isLoading = state.run == nil
                let attemptID = state.attemptID
                let generation = state.observationGeneration
                return .run { send in
                    // Idempotent: a no-op while the attempt is already running, and the cold-start
                    // recovery path when the process died with the order unfinished. It only ever
                    // resolves what was already broadcast, which is why it does not authenticate.
                    do {
                        try await peerCashOut.recoverCashOut(attemptID)
                        for await runnerState in try await peerCashOut.runnerState() {
                            await send(.runnerStateChanged(runnerState, generation: generation))
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.startupFailed(
                            String(localizable: .peerFailureGeneric),
                            generation: generation
                        ))
                    }
                }
                .cancellable(id: CancelID.runner, cancelInFlight: true)

            case .onDisappear:
                state.observationGeneration &+= 1
                return .merge(
                    .cancel(id: CancelID.runner),
                    .cancel(id: CancelID.transactionURL)
                )

            case let .runnerStateChanged(runnerState, generation):
                guard generation == state.observationGeneration else { return .none }
                state.isLoading = false
                state.startupErrorMessage = nil
                if runnerState.run(id: state.attemptID)?.isDriving == true { state.retryErrorMessage = nil }
                state.run = runnerState.run(id: state.attemptID)
                guard let hash = state.failure?.recoveryTransactionHash, state.transactionURL == nil else {
                    return .none
                }
                return .run { send in
                    await send(.transactionURLResolved(
                        try await peerCashOut.transactionURL(hash),
                        generation: generation
                    ))
                } catch: { _, _ in
                }
                .cancellable(id: CancelID.transactionURL, cancelInFlight: true)

            case let .startupFailed(message, generation):
                guard generation == state.observationGeneration else { return .none }
                state.isLoading = false
                state.startupErrorMessage = message
                return .none

            case let .transactionURLResolved(url, generation):
                guard generation == state.observationGeneration else { return .none }
                state.transactionURL = url
                return .none

            case .retryTapped:
                guard state.offersRetry else { return .none }
                state.retryErrorMessage = nil
                let attemptID = state.attemptID
                let generation = state.observationGeneration
                return .run { _ in
                    try await peerCashOut.retryCashOut(attemptID)
                } catch: { error, send in
                    // A refused authentication leaves the attempt exactly as it was and needs no
                    // words. A refused admission does: the balance this attempt was going to
                    // re-offer has been promised to something else since it failed.
                    guard !(error is PeerCashOutClientError) else { return }
                    await send(.retryFailed(error.localizedDescription, generation: generation))
                }

            case let .retryFailed(message, generation):
                guard generation == state.observationGeneration else { return .none }
                state.retryErrorMessage = message
                return .none

            case .viewOrderTapped:
                guard let depositID = state.depositID else { return .none }
                return .send(.delegate(.openOrder(depositID: depositID)))

            case .backTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }
}

extension PeerFailure {
    /// The transaction a user can be pointed at when the app cannot tell whether money moved.
    var recoveryTransactionHash: String? {
        guard case let .inspectTransaction(hash) = recovery else { return nil }
        return hash
    }

    var depositorAddress: String? {
        guard case let .inspectDepositor(address) = recovery else { return nil }
        return address
    }
}
