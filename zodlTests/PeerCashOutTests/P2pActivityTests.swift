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
        state.unindexedRuns = [run(id: attemptID, at: 400)]

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
        state.unindexedRuns = [run(id: attemptID, at: 400)]
        state.filter = filter

        #expect(state.entries.allSatisfy { entry in prefixes.contains { entry.id.hasPrefix($0) } })
        #expect(state.entries.count == prefixes.count)
    }

    /// An attempt whose deposit is now known is the order, not a second row beside it. The runner
    /// stops reporting it as unindexed, and the feed must not resurrect it from anywhere else.
    @Test func anIndexedAttemptIsReplacedByItsOrderRatherThanShownTwice() {
        var settled = run(id: attemptID, at: 400)
        settled.reconciledDepositID = "escrow_1"

        var state = P2pActivity.State.initial
        state.peerOrders = [order(id: "1", at: 400)]
        state.unindexedRuns = [settled].filter(\.isUnindexed)

        #expect(state.entries.map(\.id) == ["order:escrow_1"])
    }

    /// A refund and a Peer `createDeposit` that has not landed would spend the same Base USDC, so
    /// the action is withheld with a reason rather than failing after the user commits to it.
    @Test func refundIsBlockedWhileACashOutStillHoldsUnescrowedFunds() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: true)
        state.peerCommitted = UsdcAmount(micros: "20000000")

        #expect(!state.offersRefund)
        #expect(state.isRefundBlockedByPeer)
    }

    @Test func refundIsOfferedOnceNothingIsCommitted() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: true)
        state.peerCommitted = nil

        #expect(state.offersRefund)
        #expect(!state.isRefundBlockedByPeer)
    }

    /// Nothing to refund is a different answer from a refund that is blocked, and the screen must
    /// not explain a block that is not happening.
    @Test func anAccountWithNothingToRefundExplainsNoBlock() {
        var state = P2pActivity.State.initial
        state.account = account(canRefundToZec: false)
        state.peerCommitted = UsdcAmount(micros: "20000000")

        #expect(!state.offersRefund)
        #expect(!state.isRefundBlockedByPeer)
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

    /// The p2p.me recovery action stays in the off-ramp, which already owns its progress stream.
    @Test func aRecoverableScanAndPayOrderRoutesIntoTheOffRamp() async {
        let entry = P2pActivityEntry.scanAndPay(history(id: "a", at: 100, status: "CANCELLED"))
        let store = await TestStore(initialState: P2pActivity.State.initial) { P2pActivity() }

        await store.send(.entryTapped(entry))
        await store.receive(\.delegate.recoverScanAndPayOrder)
    }

    @Test func acompletedScanAndPayOrderHasNothingToRecoverAndDoesNotNavigate() async {
        let entry = P2pActivityEntry.scanAndPay(history(id: "a", at: 100, status: "COMPLETED"))
        let store = await TestStore(initialState: P2pActivity.State.initial) { P2pActivity() }

        await store.send(.entryTapped(entry))
    }

    private let attemptID = "0123456789abcdef0123456789abcdef"

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
