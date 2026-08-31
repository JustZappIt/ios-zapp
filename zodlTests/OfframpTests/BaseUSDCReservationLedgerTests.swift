// SPDX-License-Identifier: MIT OR Apache-2.0

import Testing
@testable import zodl_internal

struct BaseUSDCReservationLedgerTests {
    /// Both callers deliberately use the same raw 100-USDC snapshot. The ledger, not timing or the
    /// RPC balance, decides which promise fits; 80 + 50 can never both be admitted.
    @Test func concurrentPeerAndScanClaimsCannotOvercommitOneBalance() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let barrier = ReservationClaimBarrier(participants: 2)
        let balance = try amount("100000000")
        let peerAmount = try amount("80000000")
        let scanAmount = try amount("50000000")

        async let peerClaim = claim(after: barrier, ledger: ledger, owner: .peer(attemptID: "peer-1"), amount: peerAmount, balance: balance)
        async let scanClaim = claim(
            after: barrier,
            ledger: ledger,
            owner: .scanAndPay(operationID: "scan-1"),
            amount: scanAmount,
            balance: balance
        )
        let outcomes = await [peerClaim, scanClaim]

        #expect(outcomes.filter { $0 }.count == 1)
        let committed = await ledger.committed
        #expect(committed == peerAmount || committed == scanAmount)
        #expect(committed != peerAmount + scanAmount)
    }

    @Test func unreadableRecoveryFailsClosedForSpendsAndRefunds() async throws {
        let ledger = BaseUSDCReservationLedger()
        let balance = try amount("100000000")
        await ledger.markReady(.scanAndPay)
        await ledger.markReady(.onrampDelivery)
        await ledger.markUnavailable(.peer)

        #expect(await ledger.spendable(rawBalance: balance) == .unavailable)
        await #expect(throws: BaseUSDCReservationLedger.ClaimError.recoveryUnavailable) {
            try await ledger.claim(.peer(attemptID: "peer-1"), amount: try amount("1"), rawBalance: balance)
        }
        await #expect(throws: BaseUSDCReservationLedger.ClaimError.recoveryUnavailable) {
            try await ledger.claimExclusive(.refund(operationID: "refund-1"), rawBalance: balance)
        }
    }

    @Test func refundRequiresNoOutstandingBaseClaimAndThenBlocksEverySpender() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let balance = try amount("100000000")
        try await ledger.claim(.peer(attemptID: "peer-1"), amount: try amount("80000000"), rawBalance: balance)

        await #expect(throws: BaseUSDCReservationLedger.ClaimError.self) {
            try await ledger.claimExclusive(.refund(operationID: "refund-1"), rawBalance: balance)
        }

        await ledger.settle(.peer(attemptID: "peer-1"), as: .available)
        try await ledger.claimExclusive(.refund(operationID: "refund-2"), rawBalance: balance)
        await #expect(throws: BaseUSDCReservationLedger.ClaimError.self) {
            try await ledger.claim(.scanAndPay(operationID: "scan-1"), amount: try amount("1"), rawBalance: balance)
        }
        #expect(await ledger.spendable(rawBalance: balance) == .unavailable)
    }

    /// Receipt-derived settlement does not immediately release against a stale RPC response. The
    /// debit retires only once a later balance read reflects the on-chain spend.
    @Test func confirmedDebitStaysReservedUntilBalanceReflectsIt() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let original = try amount("100000000")
        let claim = try amount("80000000")
        try await ledger.claim(.peer(attemptID: "peer-1"), amount: claim, rawBalance: original)
        await ledger.settle(.peer(attemptID: "peer-1"), as: .spent)

        #expect(await ledger.spendable(rawBalance: original) == .ready(balance: original, committed: claim))

        let reflected = try amount("20000000")
        #expect(await ledger.spendable(rawBalance: reflected) == .ready(balance: reflected, committed: .zero))
    }

    /// Cold-start reconciliation learns the debit from its exact receipt before any pre-send
    /// balance exists in memory. It must not calibrate that old claim from the already-debited
    /// balance and subtract it a second time forever.
    @Test func exactRecoveryOfARestoredClaimDoesNotDoubleSubtractTheDebitedBalance() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        try await ledger.restore(.peer(attemptID: "peer-1"), amount: try amount("80000000"))
        await ledger.settle(.peer(attemptID: "peer-1"), as: .spent)

        let postDebitBalance = try amount("20000000")
        #expect(
            await ledger.spendable(rawBalance: postDebitBalance) ==
                .ready(balance: postDebitBalance, committed: .zero)
        )
    }

    @Test func equalFreshScanPaymentsNeverShareAnIdempotentOwner() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let raw = try amount("100000000")
        let amount = try amount("60000000")

        try await ledger.claim(.scanAndPay(operationID: "scan-1"), amount: amount, rawBalance: raw)
        await #expect(throws: BaseUSDCReservationLedger.ClaimError.self) {
            try await ledger.claim(.scanAndPay(operationID: "scan-2"), amount: amount, rawBalance: raw)
        }

        #expect(await ledger.committed == amount)
    }

    /// A's observed debit must not retire B. After A lands, B is rebased to the new raw balance and
    /// remains reserved until B's own debit is reflected.
    @Test func oneConfirmedDebitCannotRetireAnotherReservation() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let original = try amount("100000000")
        let peer = BaseUSDCReservationLedger.Owner.peer(attemptID: "peer-1")
        let scan = BaseUSDCReservationLedger.Owner.scanAndPay(operationID: "scan-1")
        try await ledger.claim(peer, amount: try amount("80000000"), rawBalance: original)
        try await ledger.claim(scan, amount: try amount("10000000"), rawBalance: original)

        await ledger.settle(peer, as: .spent)
        let afterPeer = try amount("20000000")
        #expect(
            await ledger.spendable(rawBalance: afterPeer) ==
                .ready(balance: afterPeer, committed: try amount("10000000"))
        )

        await ledger.settle(scan, as: .spent)
        #expect(
            await ledger.spendable(rawBalance: afterPeer) ==
                .ready(balance: afterPeer, committed: try amount("10000000"))
        )
        let afterBoth = try amount("10000000")
        #expect(await ledger.spendable(rawBalance: afterBoth) == .ready(balance: afterBoth, committed: .zero))
    }

    @Test func confirmedClaimsFromDifferentBalanceSnapshotsBothRetire() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let peer = BaseUSDCReservationLedger.Owner.peer(attemptID: "peer-1")
        let scan = BaseUSDCReservationLedger.Owner.scanAndPay(operationID: "scan-1")
        try await ledger.claim(peer, amount: try amount("40000000"), rawBalance: try amount("100000000"))
        // A landed before its delayed status arrived. B therefore has a later causal baseline.
        try await ledger.claim(scan, amount: try amount("20000000"), rawBalance: try amount("60000000"))
        await ledger.settle(peer, as: .spent)
        await ledger.settle(scan, as: .spent)

        let afterBoth = try amount("40000000")
        #expect(await ledger.spendable(rawBalance: afterBoth) == .ready(balance: afterBoth, committed: .zero))
    }

    @Test func reflectedRefundDebitClearsExclusiveAccountLock() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let refund = BaseUSDCReservationLedger.Owner.refund(operationID: "refund-1")
        try await ledger.claimExclusive(refund, rawBalance: try amount("80000000"))
        await ledger.settle(refund, as: .spent)

        #expect(await ledger.spendable(rawBalance: .zero) == .ready(balance: .zero, committed: .zero))
    }

    @Test func liveRefundAdoptsLargerDurableSweepAmount() async throws {
        let ledger = BaseUSDCReservationLedger()
        await makeReadable(ledger)
        let live = BaseUSDCReservationLedger.Owner.refund(operationID: "refund-1")
        try await ledger.claimExclusive(live, rawBalance: try amount("10000000"))

        let resolved = try await ledger.restoreOrFindRefund(
            .refund(operationID: "durable-recovery"),
            amount: try amount("80000000")
        )

        #expect(resolved == live)
        let expectedCommitted = try amount("80000000")
        #expect(await ledger.committed == expectedCommitted)
    }

    @Test func recoveredRefundFailsClosedWhenAnotherRailHasACommitment() async throws {
        let ledger = BaseUSDCReservationLedger()
        try await ledger.restore(.peer(attemptID: "peer-1"), amount: try amount("10000000"))

        await #expect(throws: BaseUSDCReservationLedger.ClaimError.recoveryUnavailable) {
            try await ledger.restoreExclusive(
                .refund(operationID: "durable-recovery"),
                amount: try amount("90000000")
            )
        }
    }

    private func amount(_ micros: String) throws -> UsdcAmount {
        try #require(UsdcAmount(micros: micros))
    }

    private func makeReadable(_ ledger: BaseUSDCReservationLedger) async {
        await ledger.markReady(.peer)
        await ledger.markReady(.scanAndPay)
        await ledger.markReady(.onrampDelivery)
    }

    private func claim(
        after barrier: ReservationClaimBarrier,
        ledger: BaseUSDCReservationLedger,
        owner: BaseUSDCReservationLedger.Owner,
        amount: UsdcAmount,
        balance: UsdcAmount
    ) async -> Bool {
        await barrier.arriveAndWait()
        do {
            try await ledger.claim(owner, amount: amount, rawBalance: balance)
            return true
        } catch {
            return false
        }
    }
}

private actor ReservationClaimBarrier {
    let participants: Int

    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participants: Int) {
        self.participants = participants
    }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals == participants {
            let waiters = waiters
            self.waiters.removeAll()
            waiters.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}
