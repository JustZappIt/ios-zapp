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

        enum SourceLoadState: Equatable, Sendable {
            case idle
            case loading
            case loaded
            case failed(String)
        }

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
        /// Only an explicit readable zero permits a refund. Loading and unavailable are security
        /// answers, not aliases for "nothing committed".
        var spendable: PeerSpendableBalance = .loading
        var isPeerAvailable = false
        var isLoading = false
        var isAddressCopied = false
        var errorMessage: String?
        var peerSource = SourceLoadState.idle
        var scanAndPaySource = SourceLoadState.idle

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
        var offersRefund: Bool {
            guard account?.canRefundToZec == true else { return false }
            guard case .ready(_, committed: .zero) = spendable else { return false }
            return true
        }

        var isRefundBlockedByPeer: Bool {
            guard account?.canRefundToZec == true else { return false }
            guard case let .ready(_, committed) = spendable else { return false }
            return committed.isPositive
        }

        var isRefundReadinessUnavailable: Bool {
            guard account?.canRefundToZec == true else { return false }
            guard case .ready = spendable else { return true }
            return false
        }

        /// An outage is not an empty financial history. Both sources must have answered
        /// successfully before the screen can conclude there is no activity.
        var showsEmptyHistory: Bool {
            entries.isEmpty && peerSource == .loaded && scanAndPaySource == .loaded
        }

        /// Only worth a filter control once both products have something in the list.
        var showsFilters: Bool {
            isPeerAvailable && !scanAndPayHistory.isEmpty
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case accountLoaded(OfframpAccountModel?)
        case peerLoaded(orders: [PeerOrder], spendable: PeerSpendableBalance, isAvailable: Bool)
        case peerLoadFailed(String)
        case scanAndPayLoaded([OfframpHistoryModel])
        case scanAndPayLoadFailed(String)
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
            case openPeerAttempt(attemptID: String, destinationCode: String)
            case openPeerOrder(depositID: String, destinationCode: String?)
            case recoverScanAndPayOrder(orderID: String)
            case refundToZec
        }
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var continuousClock

    private enum CancelID {
        case account
        case peer
        case scanAndPay
        case runner
        case copyReset
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = state.entries.isEmpty
                state.errorMessage = nil
                state.peerSource = .loading
                state.scanAndPaySource = .loading
                return .merge(
                    .run { send in
                        await send(.accountLoaded(try await offramp.accountSummary()))
                    } catch: { _, send in
                        await send(.accountLoaded(nil))
                    }
                    .cancellable(id: CancelID.account, cancelInFlight: true),
                    .run { send in
                        await send(.scanAndPayLoaded(try await offramp.history()))
                    } catch: { error, send in
                        await send(.scanAndPayLoadFailed(error.localizedDescription))
                    }
                    .cancellable(id: CancelID.scanAndPay, cancelInFlight: true),
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

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.account),
                    .cancel(id: CancelID.peer),
                    .cancel(id: CancelID.scanAndPay),
                    .cancel(id: CancelID.runner),
                    .cancel(id: CancelID.copyReset)
                )

            case let .accountLoaded(account):
                state.account = account
                return .none

            case let .peerLoaded(orders, spendable, isAvailable):
                state.peerOrders = orders
                state.spendable = spendable
                state.isPeerAvailable = isAvailable
                state.peerSource = .loaded
                state.isLoading = state.peerSource == .loading || state.scanAndPaySource == .loading
                return .none

            case let .peerLoadFailed(message):
                state.peerSource = .failed(message)
                state.spendable = .unavailable
                state.isLoading = state.peerSource == .loading || state.scanAndPaySource == .loading
                state.errorMessage = message
                return .none

            case let .scanAndPayLoaded(history):
                state.scanAndPayHistory = history
                state.scanAndPaySource = .loaded
                state.isLoading = state.peerSource == .loading || state.scanAndPaySource == .loading
                return .none

            case let .scanAndPayLoadFailed(message):
                state.scanAndPaySource = .failed(message)
                state.isLoading = state.peerSource == .loading || state.scanAndPaySource == .loading
                state.errorMessage = message
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
                    return .send(.delegate(.openPeerAttempt(attemptID: run.id, destinationCode: run.destinationCode)))
                case let .peerOrder(order):
                    return .send(.delegate(.openPeerOrder(
                        depositID: order.depositID,
                        destinationCode: order.destinationCode
                    )))
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
                return await send(.peerLoaded(orders: [], spendable: .unavailable, isAvailable: false))
            }
            let orders = try await peerCashOut.orderHistory()
            let spendable = try await peerCashOut.spendableBalance()
            await send(.peerLoaded(orders: orders, spendable: spendable, isAvailable: true))
        } catch: { error, send in
            await send(.peerLoadFailed(error.localizedDescription))
        }
        .cancellable(id: CancelID.peer, cancelInFlight: true)
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
