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

        var latest: PeerProgress? { run?.latest }
        var failure: PeerFailure? { run?.failure }
        var depositID: String? { run?.depositID }
        var isOrderLive: Bool { latest?.kind == .orderLive }

        var steps: [ZappOfframpStepItem] { PeerProgressSteps.build(from: run) }

        var title: String {
            if failure != nil { return String(localizable: .peerProgressTitleFailed) }
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
        case runnerStateChanged(PeerRunnerState)
        case transactionURLResolved(URL?)
        case retryTapped
        case viewOrderTapped
        case backTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case close
            case openOrder(depositID: String)
        }
    }

    @Dependency(\.peerCashOut) var peerCashOut

    private enum CancelID {
        case runner
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let attemptID = state.attemptID
                return .run { send in
                    // Idempotent: a no-op while the attempt is already running, and the cold-start
                    // recovery path when the process died with the order unfinished. It only ever
                    // resolves what was already broadcast, which is why it does not authenticate.
                    try await peerCashOut.recoverCashOut(attemptID)
                    for await runnerState in try await peerCashOut.runnerState() {
                        await send(.runnerStateChanged(runnerState))
                    }
                }
                .cancellable(id: CancelID.runner, cancelInFlight: true)

            case let .runnerStateChanged(runnerState):
                state.run = runnerState.run(id: state.attemptID)
                guard let hash = state.failure?.recoveryTransactionHash, state.transactionURL == nil else {
                    return .none
                }
                return .run { send in
                    await send(.transactionURLResolved(try await peerCashOut.transactionURL(hash)))
                } catch: { _, _ in
                }

            case let .transactionURLResolved(url):
                state.transactionURL = url
                return .none

            case .retryTapped:
                guard state.offersRetry else { return .none }
                let attemptID = state.attemptID
                return .run { _ in
                    try await peerCashOut.retryCashOut(attemptID)
                } catch: { _, _ in
                    // A refused authentication leaves the attempt exactly as it was.
                }

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
