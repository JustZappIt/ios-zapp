// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

/// The unified feed. Two products with separate records — one read from an indexer keyed on the
/// smart account, the other from a subgraph keyed on a relay identity — have to merge into one
/// list without either half being able to hide the other.
struct P2pActivityTests {
    @Test func bothProductsAppearNewestFirst() {
        var state = P2pActivity.State.initial
        state.peerOrders = [order(id: "1", at: 200)]
        state.scanAndPayHistory = [history(id: "a", at: 300), history(id: "b", at: 100)]
        state.runs = [run(id: attemptID, at: 400)]

        #expect(state.entries.map(\.id) == ["attempt:\(attemptID)", "p2pme:a", "order:escrow_1", "p2pme:b"])
    }

    /// Ties must not reorder between two reads that report the same timestamp.
    @Test func rowsWithTheSameTimestampKeepAStableOrder() {
        var state = P2pActivity.State.initial
        state.scanAndPayHistory = [history(id: "b", at: 100), history(id: "a", at: 100)]

        #expect(state.entries.map(\.id) == ["p2pme:a", "p2pme:b"])
        #expect(state.entries.map(\.id) == state.entries.map(\.id))
    }

    @Test(arguments: [
        (P2pActivity.State.Filter.peer, ["attempt", "order"]),
        (.scanAndPay, ["p2pme"])
    ])
    func filteringKeepsOnlyOneProvider(filter: P2pActivity.State.Filter, prefixes: [String]) {
        var state = P2pActivity.State.initial
        state.peerOrders = [order(id: "1", at: 200)]
        state.scanAndPayHistory = [history(id: "a", at: 300)]
        state.runs = [run(id: attemptID, at: 400)]
        state.filter = filter

        #expect(state.entries.allSatisfy { entry in prefixes.contains { entry.id.hasPrefix($0) } })
        #expect(state.entries.count == prefixes.count)
    }

    /// An attempt whose deposit is now listed is the order, not a second row beside it.
    @Test func anIndexedAttemptIsReplacedByItsOrderRatherThanShownTwice() {
        var settled = run(id: attemptID, at: 400)
        settled.reconciledDepositID = "escrow_1"

        var state = P2pActivity.State.initial
        state.peerOrders = [order(id: "1", at: 400)]
        state.runs = [settled]

        #expect(state.entries.map(\.id) == ["order:escrow_1"])
    }

    /// The deposit id is resolved from a transaction receipt, which runs ahead of the indexer the
    /// order list is read from. Dropping the row the moment the id exists leaves the amount
    /// subtracted from the balance with nothing on screen accounting for it.
    @Test func aReconciledAttemptKeepsItsRowUntilTheOrderListCanShowIt() {
        var settled = run(id: attemptID, at: 400)
        settled.reconciledDepositID = "escrow_1"

        var state = P2pActivity.State.initial
        state.runs = [settled]

        #expect(state.entries.map(\.id) == ["attempt:\(attemptID)"])

        state.peerOrders = [order(id: "1", at: 400)]
        #expect(state.entries.map(\.id) == ["order:escrow_1"])
    }

    /// Its progress screen has nothing left to resolve once the deposit is known, so the row opens
    /// the order it already belongs to.
    @MainActor
    @Test func tappingAReconciledAttemptOpensItsOrder() async {
        var settled = run(id: attemptID, at: 400)
        settled.reconciledDepositID = "escrow_1"
        let store = TestStore(initialState: P2pActivity.State.initial) { P2pActivity() }

        await store.send(.entryTapped(.peerAttempt(settled)))
        await store.receive(\.delegate.openPeerOrder)
    }

    /// The refund gate is a Base-wide reading. A build with no Peer rails still has a balance to
    /// recover, and a Peer indexer outage is not a reason to hide fund recovery.
    @MainActor
    @Test func aPeerOrderOutageDoesNotHideTheRefundAction() async {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: true)
        let store = TestStore(initialState: state) { P2pActivity() }

        await store.send(.spendableLoaded(.ready(balance: usdc("20000000"), committed: .zero))) {
            $0.spendable = .ready(balance: self.usdc("20000000"), committed: .zero)
        }
        await store.send(.peerLoadFailed("Indexer unavailable")) {
            $0.peerSource = .failed("Indexer unavailable")
            $0.errorMessage = "Indexer unavailable"
        }

        #expect(store.state.offersRefund)
    }

    /// A refund and a Peer `createDeposit` that has not landed would spend the same Base USDC, so
    /// the action is withheld with a reason rather than failing after the user commits to it.
    @Test func refundIsBlockedWhileACashOutStillHoldsUnescrowedFunds() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: true)
        state.spendable = .ready(
            balance: UsdcAmount(micros: "20000000") ?? .zero,
            committed: UsdcAmount(micros: "20000000") ?? .zero
        )

        #expect(!state.offersRefund)
        #expect(state.isRefundBlockedByPeer)
    }

    @Test func refundIsOfferedOnceNothingIsCommitted() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: true)
        state.spendable = .ready(balance: UsdcAmount(micros: "20000000") ?? .zero, committed: .zero)

        #expect(state.offersRefund)
        #expect(!state.isRefundBlockedByPeer)
    }

    /// Nothing to refund is a different answer from a refund that is blocked, and the screen must
    /// not explain a block that is not happening.
    @Test func anAccountWithNothingToRefundExplainsNoBlock() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: false)
        state.spendable = .ready(
            balance: UsdcAmount(micros: "20000000") ?? .zero,
            committed: UsdcAmount(micros: "20000000") ?? .zero
        )

        #expect(!state.offersRefund)
        #expect(!state.isRefundBlockedByPeer)
    }

    @Test func unreadableReservationStateNeverEnablesRefund() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: true)
        state.spendable = .unavailable

        #expect(!state.offersRefund)
        #expect(!state.isRefundBlockedByPeer)
        #expect(state.isRefundReadinessUnavailable)
    }

    @Test func aFailedSourceDoesNotTurnNoRowsIntoEmptyHistory() {
        var state = P2pActivity.State.initial
        state.peerSource = .loaded
        state.scanAndPaySource = .failed("offline")

        #expect(state.entries.isEmpty)
        #expect(!state.showsEmptyHistory)

        state.scanAndPaySource = .loaded
        #expect(state.showsEmptyHistory)
    }

    @MainActor
    @Test func scanAndPayFailurePreservesLastKnownFinancialRows() async {
        let existing = history(id: "known", at: 100)
        var state = P2pActivity.State.initial
        state.scanAndPayHistory = [existing]
        state.scanAndPaySource = .loading
        let store = TestStore(initialState: state) { P2pActivity() }

        await store.send(.scanAndPayLoadFailed("Indexer unavailable")) {
            $0.scanAndPaySource = .failed("Indexer unavailable")
            $0.errorMessage = "Indexer unavailable"
        }

        #expect(store.state.scanAndPayHistory == [existing])
        #expect(store.state.entries.map(\.id) == ["p2pme:known"])
    }

    /// A filter control over a list with only one product in it is noise.
    @Test func filtersAppearOnlyWhenBothProductsHaveSomethingToShow() {
        var state = P2pActivity.State.initial
        state.isPeerAvailable = true
        #expect(!state.showsFilters)

        state.scanAndPayHistory = [history(id: "a", at: 100)]
        #expect(state.showsFilters)

        state.isPeerAvailable = false
        #expect(!state.showsFilters)
    }

    /// Cancelling already returned the order's USDC to Base, so there is no per-order recovery to
    /// offer — moving that balance to ZEC is the balance card's refund.
    @Test func aCancelledScanAndPayOrderDoesNotNavigate() async {
        var state = P2pActivity.State.initial
        state.spendable = .ready(balance: usdc("20000000"), committed: .zero)
        let entry = P2pActivityEntry.scanAndPay(history(id: "a", at: 100, status: "CANCELLED"))
        let store = await TestStore(initialState: state) { P2pActivity() }

        await store.send(.entryTapped(entry))
    }

    @Test func acompletedScanAndPayOrderHasNothingToRecoverAndDoesNotNavigate() async {
        let entry = P2pActivityEntry.scanAndPay(history(id: "a", at: 100, status: "COMPLETED"))
        let store = await TestStore(initialState: P2pActivity.State.initial) { P2pActivity() }

        await store.send(.entryTapped(entry))
    }

    private let attemptID = "0123456789abcdef0123456789abcdef"

    private func usdc(_ micros: String) -> UsdcAmount {
        UsdcAmount(micros: micros) ?? .zero
    }

    private func run(id: String, at seconds: TimeInterval) -> PeerRun {
        PeerRun(
            id: id,
            destinationCode: "revolut",
            amount: UsdcAmount(micros: "20000000") ?? .zero,
            currencyCodes: ["EUR"],
            startedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func order(id: String, at seconds: TimeInterval) -> PeerOrder {
        PeerOrder(
            depositID: "escrow_\(id)",
            phase: .waiting,
            isFinished: false,
            acceptingIntents: true,
            gross: UsdcAmount(micros: "20000000") ?? .zero,
            remaining: UsdcAmount(micros: "20000000") ?? .zero,
            sold: .zero,
            locked: .zero,
            withdrawn: .zero,
            withdrawable: UsdcAmount(micros: "20000000") ?? .zero,
            destinationCode: "revolut",
            currencyCodes: ["EUR"],
            buyerLegs: [],
            offersWithdrawal: true,
            offersMatchingToggle: false,
            isHiddenFromBuyers: false,
            openedAt: Date(timeIntervalSince1970: seconds),
            lastActivityAt: Date(timeIntervalSince1970: seconds),
            explorerURL: nil
        )
    }

    private func history(id: String, at seconds: TimeInterval, status: String = "COMPLETED") -> OfframpHistoryModel {
        OfframpHistoryModel(
            id: id,
            status: status,
            orderType: "PAY",
            currencyCode: "INR",
            usdcMicros: "1190000",
            fiatMicros: "100000000",
            placedAt: Date(timeIntervalSince1970: seconds),
            completedAt: Date(timeIntervalSince1970: seconds),
            cancelledAt: nil,
            paymentAddress: "merchant@example",
            merchantAddress: "0xmerchant",
            fixedFeeMicros: nil
        )
    }

    private func account(canRefundToZec: Bool) -> OfframpAccountModel {
        OfframpAccountModel(
            address: "0x00000000000000000000000000000000000000aa",
            balanceMicros: "20000000",
            balanceDisplay: "20",
            explorerURL: nil,
            canBridgeToBase: true,
            canRefundToZec: canRefundToZec
        )
    }
}
