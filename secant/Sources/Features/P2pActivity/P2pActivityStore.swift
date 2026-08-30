// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// One row of P2P history, from whichever product produced it.
enum P2pActivityEntry: Equatable, Identifiable, Sendable {
    /// A cash-out the chain cannot answer for yet. It has no order to link to, and without a row of
    /// its own the amount it reserves is missing from the balance with nothing to explain it.
    case peerAttempt(PeerRun)
    case peerOrder(PeerOrder)
    case scanAndPay(OfframpHistoryModel)

    var id: String {
        switch self {
        case let .peerAttempt(run): return "attempt:\(run.id)"
        case let .peerOrder(order): return "order:\(order.depositID)"
        case let .scanAndPay(item): return "p2pme:\(item.id)"
        }
    }

    var provider: P2pProvider {
        switch self {
        case .peerAttempt, .peerOrder: return .peer
        case .scanAndPay: return .p2pMe
        }
    }

    /// What the row is sorted by. An attempt has no chain time yet, so it uses when the user
    /// started it — which is the only moment that exists for it.
    var sortDate: Date {
        switch self {
        case let .peerAttempt(run): return run.startedAt
        case let .peerOrder(order): return order.lastActivityAt ?? order.openedAt ?? .distantPast
        case let .scanAndPay(item): return item.completedAt ?? item.cancelledAt ?? item.placedAt ?? .distantPast
        }
    }
}

/// Every P2P order in one place, whichever product opened it.
///
/// Peer and p2p.me are separate rails with separate records — one is read from an indexer keyed on
/// the smart account, the other from a subgraph keyed on a relay identity — and a user who has used
/// both should not have to remember which screen holds which.
@Reducer
struct P2pActivity {
    @ObservableState
    struct State: Equatable {
        static let initial = State()

        enum Filter: String, Equatable, Sendable, CaseIterable {
            case all
            case peer
            case scanAndPay
        }

        var filter: Filter = .all
        var account: OfframpAccountModel?
        var peerOrders: [PeerOrder] = []
        var unindexedRuns: [PeerRun] = []
        var scanAndPayHistory: [OfframpHistoryModel] = []
        /// USDC promised to Peer attempts that have not escrowed it yet. While this is positive a
        /// refund and a pending `createDeposit` would spend the same coins.
        var peerCommitted: UsdcAmount?
        var isPeerAvailable = false
        var isLoading = false
        var isAddressCopied = false
        var errorMessage: String?

        var entries: [P2pActivityEntry] {
            let all = unindexedRuns.map(P2pActivityEntry.peerAttempt)
                + peerOrders.map(P2pActivityEntry.peerOrder)
                + scanAndPayHistory.map(P2pActivityEntry.scanAndPay)
            return all
                .filter { entry in filter.provider.map { $0 == entry.provider } ?? true }
                // Newest first, ties broken on the id so the list cannot reorder itself between two
                // reads that report the same timestamp.
                .sorted { lhs, rhs in
                    lhs.sortDate == rhs.sortDate ? lhs.id < rhs.id : lhs.sortDate > rhs.sortDate
                }
        }

        /// Offered only where the whole balance is genuinely free. A cash-out mid-flight is the one
        /// case where the balance is visible but already spoken for.
        var offersRefund: Bool { account?.canRefundToZec == true && peerCommitted == nil }

        var isRefundBlockedByPeer: Bool { account?.canRefundToZec == true && peerCommitted != nil }

        /// Only worth a filter control once both products have something in the list.
        var showsFilters: Bool {
            isPeerAvailable && !scanAndPayHistory.isEmpty
        }
    }

    enum Action: Equatable {
        case onAppear
        case accountLoaded(OfframpAccountModel?)
        case peerLoaded(orders: [PeerOrder], committed: UsdcAmount?, isAvailable: Bool)
        case scanAndPayLoaded([OfframpHistoryModel])
        case runnerStateChanged(PeerRunnerState)
        case loadFailed(String)
        case filterTapped(State.Filter)
        case copyAddressTapped
        case addressCopyReset
        case entryTapped(P2pActivityEntry)
        case refundTapped
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
            case openPeerAttempt(attemptID: String)
            case openPeerOrder(depositID: String)
            case recoverScanAndPayOrder(orderID: String)
            case refundToZec
        }
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var continuousClock

    private enum CancelID {
        case runner
        case copyReset
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.errorMessage = nil
                return .merge(
                    .run { send in
                        // Independent reads: one rail being unreachable must not empty the other's
                        // half of the list.
                        await send(.accountLoaded(try? await offramp.accountSummary()))
                        await send(.scanAndPayLoaded((try? await offramp.history()) ?? []))
                    },
                    loadPeer(),
                    .run { send in
                        for await runnerState in try await peerCashOut.runnerState() {
                            await send(.runnerStateChanged(runnerState))
                        }
                    } catch: { _, _ in
                        // No Peer rails on this build; the p2p.me half of the list still loads.
                    }
                    .cancellable(id: CancelID.runner, cancelInFlight: true)
                )

            case let .accountLoaded(account):
                state.account = account
                state.isLoading = false
                return .none

            case let .peerLoaded(orders, committed, isAvailable):
                state.peerOrders = orders
                state.peerCommitted = committed
                state.isPeerAvailable = isAvailable
                return .none

            case let .scanAndPayLoaded(history):
                state.scanAndPayHistory = history
                return .none

            case let .runnerStateChanged(runnerState):
                state.unindexedRuns = runnerState.runs.filter(\.isUnindexed)
                // An attempt settling turns into an order and frees what it reserved, so both the
                // list and the refund gate are stale the moment one does.
                return loadPeer()

            case let .loadFailed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none

            case let .filterTapped(filter):
                state.filter = filter
                return .none

            case .copyAddressTapped:
                guard let address = state.account?.address else { return .none }
                pasteboard.setString(RedactableString(address))
                state.isAddressCopied = true
                return .run { send in
                    try await continuousClock.sleep(for: .seconds(2))
                    await send(.addressCopyReset)
                }
                .cancellable(id: CancelID.copyReset, cancelInFlight: true)

            case .addressCopyReset:
                state.isAddressCopied = false
                return .none

            case let .entryTapped(entry):
                switch entry {
                case let .peerAttempt(run):
                    return .send(.delegate(.openPeerAttempt(attemptID: run.id)))
                case let .peerOrder(order):
                    return .send(.delegate(.openPeerOrder(depositID: order.depositID)))
                case let .scanAndPay(item):
                    guard item.canRecoverEscrow else { return .none }
                    return .send(.delegate(.recoverScanAndPayOrder(orderID: item.id)))
                }

            case .refundTapped:
                guard state.offersRefund else { return .none }
                return .send(.delegate(.refundToZec))

            case .backTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }

    /// Peer is mainnet-only, so an unavailable build reports nothing rather than failing — the
    /// p2p.me half of the list is still worth showing.
    private func loadPeer() -> Effect<Action> {
        .run { send in
            let capabilities = try await peerCashOut.capabilities()
            guard capabilities.isAvailable else {
                return await send(.peerLoaded(orders: [], committed: nil, isAvailable: false))
            }
            let orders = try await peerCashOut.orderHistory()
            let committed = try? await peerCashOut.spendableBalance().committed
            await send(.peerLoaded(orders: orders, committed: committed, isAvailable: true))
        } catch: { _, send in
            await send(.peerLoaded(orders: [], committed: nil, isAvailable: false))
        }
    }
}

extension P2pActivity.State.Filter {
    var provider: P2pProvider? {
        switch self {
        case .all: return nil
        case .peer: return .peer
        case .scanAndPay: return .p2pMe
        }
    }

    var label: String {
        switch self {
        case .all: return String(localizable: .p2pActivityFilterAll)
        case .peer: return String(localizable: .p2pActivityFilterPeer)
        case .scanAndPay: return String(localizable: .p2pActivityFilterScanAndPay)
        }
    }
}
