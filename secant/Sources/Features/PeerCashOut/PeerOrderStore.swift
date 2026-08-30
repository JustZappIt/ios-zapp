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
        case orderChanged(PeerOrder, readAt: Date)
        case refreshTapped
        case readFailed(String)
        case runnerStateChanged(PeerRunnerState)
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
        case runner
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = state.order == nil
                let depositID = state.depositID
                return .merge(
                    .run { send in
                        for await progress in try await peerCashOut.observeOrder(depositID) {
                            guard let order = progress.order else { continue }
                            await send(.orderChanged(order, readAt: date.now()))
                        }
                    } catch: { error, send in
                        await send(.readFailed(error.localizedDescription))
                    }
                    .cancellable(id: CancelID.poll, cancelInFlight: true),
                    .run { send in
                        for await runnerState in try await peerCashOut.runnerState() {
                            await send(.runnerStateChanged(runnerState))
                        }
                    }
                    .cancellable(id: CancelID.runner, cancelInFlight: true)
                )

            case let .orderChanged(order, readAt):
                state.isLoading = false
                state.order = order
                state.readAt = readAt
                state.readErrorMessage = nil
                return .none

            case .refreshTapped:
                let depositID = state.depositID
                return .run { send in
                    guard let order = try await peerCashOut.order(depositID) else {
                        return await send(.readFailed(String(localizable: .peerOrderReadFailed)))
                    }
                    await send(.orderChanged(order, readAt: date.now()))
                } catch: { error, send in
                    await send(.readFailed(error.localizedDescription))
                }

            case let .readFailed(message):
                state.isLoading = false
                // The snapshot already on screen is kept: it is the last thing the chain actually
                // said, and blanking it would read as the order having gone away.
                state.readErrorMessage = message
                return .none

            case let .runnerStateChanged(runnerState):
                state.action = runnerState.orderActions[state.depositID]
                return .none

            case .withdrawTapped:
                guard state.offersWithdrawal, let order = state.order, order.withdrawable.isPositive else {
                    return .none
                }
                let depositID = state.depositID
                let amount = order.withdrawable
                return .run { _ in
                    try await peerCashOut.withdraw(depositID, amount)
                } catch: { _, _ in
                    // A refused authentication leaves the escrow exactly as it was.
                }

            case .matchingToggleTapped:
                guard state.offersMatchingToggle, let order = state.order else { return .none }
                let depositID = state.depositID
                let accepting = !order.acceptingIntents
                return .run { _ in
                    try await peerCashOut.setAcceptingIntents(depositID, accepting)
                } catch: { _, _ in
                }

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
}
