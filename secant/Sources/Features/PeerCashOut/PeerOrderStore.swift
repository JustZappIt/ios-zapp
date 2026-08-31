// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// One order, loaded from its deposit id alone.
///
/// That is the whole point of the screen: everything shown comes from the chain and the indexer, so
/// the order survives process death, a reinstall, and a different device on the same seed. Nothing
/// here is remembered locally.
@Reducer
struct PeerOrderDetail {
    @ObservableState
    struct State: Equatable {
        let depositID: String

        var order: PeerOrder?
        /// When the visible figures were last read. An action that has already moved the escrow is
        /// only released once a read *after* it lands, or the buttons would offer an action the
        /// numbers on screen cannot back.
        var readAt: Date?
        var action: PeerOrderAction?
        /// Non-destructive: the last known snapshot stays on screen beneath it.
        var readErrorMessage: String?
        var isLoading = false
        /// Every read belongs to the order-action state that started it. Cancelling an effect is
        /// advisory, so the generation is also checked when a dependency eventually answers.
        var readGeneration = 0
        var runnerGeneration = 0

        /// Kept even when a status has no order. In particular, KMP reports indexer and chain-read
        /// failures as terminal progress values rather than throwing the stream.
        var latestProgress: PeerProgress?

        var isBusy: Bool { action?.awaitsConfirmation(orderReadAt: readAt) ?? false }

        var offersWithdrawal: Bool { order?.offersWithdrawal == true && !isBusy }

        /// Offered only where a withdrawal cannot reach — live intents holding the whole balance —
        /// because withdrawing prunes on its own and is what stopping matching was in service of.
        var offersMatchingToggle: Bool { order?.offersMatchingToggle == true && !isBusy }

        var actionFailure: PeerFailure? { action?.failure }

        var amountRows: [ZappCompactLedgerRow] {
            guard let order else { return [] }
            var rows = [
                ZappCompactLedgerRow(
                    label: String(localizable: .peerOrderRowOffered),
                    value: usdc(order.gross)
                ),
                ZappCompactLedgerRow(
                    label: String(localizable: .peerOrderRowSold),
                    value: usdc(order.sold)
                ),
                ZappCompactLedgerRow(
                    label: String(localizable: .peerOrderRowRemaining),
                    value: usdc(order.remaining)
                )
            ]
            if order.locked.isPositive {
                rows.append(
                    ZappCompactLedgerRow(label: String(localizable: .peerOrderRowLocked), value: usdc(order.locked))
                )
            }
            if order.withdrawn.isPositive {
                rows.append(
                    ZappCompactLedgerRow(
                        label: String(localizable: .peerOrderRowWithdrawn),
                        value: usdc(order.withdrawn)
                    )
                )
            }
            rows.append(
                ZappCompactLedgerRow(
                    label: String(localizable: .peerOrderRowCurrencies),
                    value: order.currencyCodes.joined(separator: " · ")
                )
            )
            return rows
        }

        private func usdc(_ amount: UsdcAmount) -> String {
            String(localizable: .peerUsdcAmount(amount.display))
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case orderProgressReceived(PeerProgress, readStartedAt: Date, generation: Int)
        case refreshCompleted(PeerOrder?, readStartedAt: Date, generation: Int)
        case refreshTapped
        case observationFailed(String, generation: Int)
        case refreshFailed(String, generation: Int)
        case runnerStateChanged(PeerRunnerState, generation: Int)
        case withdrawTapped
        case matchingToggleTapped
        case dismissActionErrorTapped
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
        }
    }

    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.date) var date

    private enum CancelID {
        case poll
        case refresh
        case runner
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = state.order == nil
                state.readGeneration &+= 1
                state.runnerGeneration &+= 1
                let readGeneration = state.readGeneration
                let runnerGeneration = state.runnerGeneration
                return .merge(
                    observeOrder(state.depositID, generation: readGeneration),
                    .run { send in
                        for await runnerState in try await peerCashOut.runnerState() {
                            await send(.runnerStateChanged(runnerState, generation: runnerGeneration))
                        }
                    }
                    .cancellable(id: CancelID.runner, cancelInFlight: true)
                )

            case .onDisappear:
                // Invalidate first: a dependency that ignores cancellation can still answer, but
                // an old-generation answer is no longer allowed to stamp this screen.
                state.readGeneration &+= 1
                state.runnerGeneration &+= 1
                return .merge(
                    .cancel(id: CancelID.poll),
                    .cancel(id: CancelID.refresh),
                    .cancel(id: CancelID.runner)
                )

            case let .orderProgressReceived(progress, readStartedAt, generation):
                guard generation == state.readGeneration else { return .none }
                state.latestProgress = progress
                guard let order = progress.order else {
                    if let failure = progress.failure {
                        state.isLoading = false
                        state.readErrorMessage = failure.message
                    } else if progress.isTerminal {
                        state.isLoading = false
                        state.readErrorMessage = String(localizable: .peerOrderReadFailed)
                    }
                    return .none
                }
                updateSnapshot(&state, order: order, readStartedAt: readStartedAt)
                return .none

            case let .refreshCompleted(order, readStartedAt, generation):
                guard generation == state.readGeneration else { return .none }
                if let order {
                    updateSnapshot(&state, order: order, readStartedAt: readStartedAt)
                } else {
                    state.isLoading = false
                    state.readErrorMessage = String(localizable: .peerOrderReadFailed)
                }
                // A refresh replaces the prior subscription. Start the next observation only
                // after this request completed, so all of its snapshots are causally newer.
                return observeOrder(state.depositID, generation: generation)

            case .refreshTapped:
                state.readGeneration &+= 1
                let generation = state.readGeneration
                let depositID = state.depositID
                return .merge(
                    .cancel(id: CancelID.poll),
                    .run { send in
                        // This is deliberately captured before the suspension. Response time says
                        // nothing about whether the chain read preceded an escrow mutation.
                        let readStartedAt = date.now()
                        let order = try await peerCashOut.order(depositID)
                        await send(.refreshCompleted(order, readStartedAt: readStartedAt, generation: generation))
                    } catch: { error, send in
                        guard !Task.isCancelled else { return }
                        await send(.refreshFailed(error.localizedDescription, generation: generation))
                    }
                    .cancellable(id: CancelID.refresh, cancelInFlight: true)
                )

            case let .observationFailed(message, generation):
                guard generation == state.readGeneration else { return .none }
                state.isLoading = false
                // The snapshot already on screen is kept: it is the last thing the chain actually
                // said, and blanking it would read as the order having gone away.
                state.readErrorMessage = message
                return .none

            case let .refreshFailed(message, generation):
                guard generation == state.readGeneration else { return .none }
                state.isLoading = false
                state.readErrorMessage = message
                return observeOrder(state.depositID, generation: generation)

            case let .runnerStateChanged(runnerState, generation):
                guard generation == state.runnerGeneration else { return .none }
                let previous = state.action
                let next = runnerState.orderActions[state.depositID]
                state.action = next
                guard readBoundaryChanged(from: previous, to: next) else { return .none }
                return restartObservation(&state)

            case .withdrawTapped:
                guard state.offersWithdrawal, let order = state.order, order.withdrawable.isPositive else {
                    return .none
                }
                let depositID = state.depositID
                let amount = order.withdrawable
                return .merge(
                    restartObservation(&state),
                    .run { _ in
                        try await peerCashOut.withdraw(depositID, amount)
                    } catch: { _, _ in
                        // A refused authentication leaves the escrow exactly as it was.
                    }
                )

            case .matchingToggleTapped:
                guard state.offersMatchingToggle, let order = state.order else { return .none }
                let depositID = state.depositID
                let accepting = !order.acceptingIntents
                return .merge(
                    restartObservation(&state),
                    .run { _ in
                        try await peerCashOut.setAcceptingIntents(depositID, accepting)
                    } catch: { _, _ in
                    }
                )

            case .dismissActionErrorTapped:
                let depositID = state.depositID
                state.action = nil
                return .run { _ in await peerCashOut.clearOrderAction(depositID) }

            case .backTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }

    private func restartObservation(_ state: inout State) -> Effect<Action> {
        state.readGeneration &+= 1
        return observeOrder(state.depositID, generation: state.readGeneration)
    }

    private func observeOrder(_ depositID: String, generation: Int) -> Effect<Action> {
        .run { send in
            // KMP's flow may answer after it has been cancelled. The generation identifies which
            // order-action boundary this read began on; the timestamp identifies which side of a
            // settled transaction its visible figures came from.
            let readStartedAt = date.now()
            for await progress in try await peerCashOut.observeOrder(depositID) {
                await send(.orderProgressReceived(
                    progress,
                    readStartedAt: readStartedAt,
                    generation: generation
                ))
            }
        } catch: { error, send in
            guard !Task.isCancelled else { return }
            await send(.observationFailed(error.localizedDescription, generation: generation))
        }
        .cancellable(id: CancelID.poll, cancelInFlight: true)
    }

    private func updateSnapshot(_ state: inout State, order: PeerOrder, readStartedAt: Date) {
        // Two current-generation reads can overlap during a manual refresh. A response from the
        // older request cannot replace a snapshot whose read began later.
        guard state.readAt.map({ readStartedAt >= $0 }) ?? true else { return }
        state.isLoading = false
        state.order = order
        state.readAt = readStartedAt
        state.readErrorMessage = nil
    }

    private func readBoundaryChanged(from previous: PeerOrderAction?, to next: PeerOrderAction?) -> Bool {
        previous?.isRunning != next?.isRunning || previous?.settledAt != next?.settledAt
    }
}
