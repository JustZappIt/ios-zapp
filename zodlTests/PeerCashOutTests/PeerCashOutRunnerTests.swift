// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

/// The runner's bookkeeping, exercised without a wallet session. Without a bound client no protocol
/// work starts, which is exactly what makes the reservation, deduplication and teardown rules
/// testable on their own: they are the parts that must hold before anything is broadcast.
struct PeerCashOutRunnerTests {
    /// The amount screen validates against a balance with committed attempts already subtracted, so
    /// a reservation nobody can observe yet is what lets a second tap spend the same coins. It has
    /// to be recorded before `start` returns, not a frame later.
    @Test func startingAnAttemptReservesItsAmountImmediately() async throws {
        let runner = await readyRunner()
        let id = await runner.newAttemptID(byteCount: 16)

        let started = try await runner.start(
            id: id,
            draft: draft(amount: "20000000"),
            rawBalance: amount("100000000")
        )

        #expect(started == id)
        let state = await runner.currentState
        #expect(state.runs.count == 1)
        #expect(state.committedByRuns.microsString == "20000000")
    }

    /// A repeat start on the same attempt must not rewind one already in flight.
    @Test func aRepeatStartIsDroppedRatherThanRestarting() async throws {
        let runner = await readyRunner()
        let id = await runner.newAttemptID(byteCount: 16)

        _ = try await runner.start(id: id, draft: draft(amount: "20000000"), rawBalance: amount("100000000"))
        let second = try await runner.start(id: id, draft: draft(amount: "50000000"), rawBalance: amount("100000000"))

        #expect(second == nil)
        let state = await runner.currentState
        #expect(state.runs.count == 1)
        #expect(state.committedByRuns.microsString == "20000000")
    }

    /// Several cash-outs can be unfinished at once, and each reserves its own amount.
    @Test func concurrentAttemptsEachReserveTheirOwnAmount() async throws {
        let runner = await readyRunner()
        let first = await runner.newAttemptID(byteCount: 16)
        let second = await runner.newAttemptID(byteCount: 16)

        _ = try await runner.start(id: first, draft: draft(amount: "20000000"), rawBalance: amount("100000000"))
        _ = try await runner.start(id: second, draft: draft(amount: "30000000"), rawBalance: amount("100000000"))

        let state = await runner.currentState
        #expect(state.runs.count == 2)
        #expect(state.committedByRuns.microsString == "50000000")
    }

    @Test func attemptIdsAreDistinctAndTheRightLength() async {
        let runner = PeerCashOutRunner()
        var ids: Set<String> = []
        for _ in 0..<32 {
            ids.insert(await runner.newAttemptID(byteCount: 16))
        }

        #expect(ids.count == 32)
        #expect(ids.allSatisfy { $0.count == 32 })
        #expect(ids.allSatisfy { $0.allSatisfy(\.isHexDigit) })
    }

    /// Wallet-scoped state on an app-lifetime actor: a seed change must not leave the previous
    /// wallet's attempts reserving a balance that is no longer theirs.
    @Test func resetClearsEveryReservation() async throws {
        let runner = await readyRunner()
        let id = await runner.newAttemptID(byteCount: 16)
        _ = try await runner.start(id: id, draft: draft(amount: "20000000"), rawBalance: amount("100000000"))

        await runner.reset()

        let state = await runner.currentState
        #expect(state.runs.isEmpty)
        #expect(state.committedByRuns == .zero)
    }

    /// A screen that subscribes after the work started still needs to see it, so the current state
    /// is published on subscription rather than only on the next change.
    @Test func subscribingPublishesTheCurrentStateImmediately() async throws {
        let runner = await readyRunner()
        let id = await runner.newAttemptID(byteCount: 16)
        _ = try await runner.start(id: id, draft: draft(amount: "20000000"), rawBalance: amount("100000000"))

        var iterator = await runner.observe().makeAsyncIterator()
        let first = try #require(await iterator.next())

        #expect(first.run(id: id)?.amount.microsString == "20000000")
    }

    /// A finished action is kept, stamped, so the screen has something to hold its buttons closed
    /// until a later read lands. Clearing it is the caller's explicit decision.
    @Test func aSettledActionHoldsTheControlsUntilAReadAfterIt() {
        let settled = Date(timeIntervalSince1970: 1_700_000_100)
        let action = PeerOrderAction(
            depositID: "escrow_1",
            kind: .withdraw,
            latest: nil,
            isRunning: false,
            settledAt: settled
        )

        #expect(action.awaitsConfirmation(orderReadAt: nil))
        #expect(action.awaitsConfirmation(orderReadAt: settled.addingTimeInterval(-1)))
        #expect(!action.awaitsConfirmation(orderReadAt: settled.addingTimeInterval(1)))
    }

    @Test func aRunningActionAlwaysHoldsTheControls() {
        let action = PeerOrderAction(depositID: "escrow_1", kind: .setAccepting, latest: nil, isRunning: true)

        #expect(action.awaitsConfirmation(orderReadAt: Date.distantFuture))
    }

    @Test func clearingAFinishedActionDropsItsRecord() async {
        let runner = PeerCashOutRunner()

        await runner.clearOrderAction(depositID: "escrow_1")

        #expect(await runner.currentState.orderActions["escrow_1"] == nil)
    }

    /// `RECOVERY_STATE_UNREADABLE` explicitly says the outcome is unknown. It holds funds even
    /// when retry/recovery has cleared the transient `creatingDeposit` history.
    @Test func unknownFailureWithoutStatusHistoryStillHoldsFunds() {
        var run = PeerRun(
            id: "attempt",
            destinationCode: "revolut",
            amount: amount("20000000"),
            currencyCodes: ["EUR"],
            startedAt: .distantPast
        )
        run.statuses = [failure(nothingEscrowed: false)]

        #expect(run.holdsFunds)
    }

    /// A pre-send failure released what the attempt reserved. Between then and Try again another
    /// spender may have been admitted against the same coins, so the retry has to re-admit rather
    /// than assume the amount is still its own.
    @Test func retryingReclaimsTheReservationTheFailureReleased() async throws {
        let reservations = BaseUSDCReservationLedger()
        let runner = await readyRunner(reservations)
        let id = await runner.newAttemptID(byteCount: 16)
        _ = try await runner.start(id: id, draft: draft(amount: "20000000"), rawBalance: amount("100000000"))
        await reservations.settle(.peer(attemptID: id), as: .available)
        #expect(await reservations.committed == .zero)

        try await runner.retry(id: id, rawBalance: amount("100000000"), sessionGeneration: 0)

        #expect(await reservations.committed.microsString == "20000000")
    }

    /// The whole point of re-admitting: a balance already promised elsewhere must refuse the retry
    /// instead of letting a second broadcast spend the same coins.
    @Test func retryingIsRefusedWhenTheBalanceIsNoLongerAvailable() async throws {
        let reservations = BaseUSDCReservationLedger()
        let runner = await readyRunner(reservations)
        let id = await runner.newAttemptID(byteCount: 16)
        _ = try await runner.start(id: id, draft: draft(amount: "20000000"), rawBalance: amount("100000000"))
        await reservations.settle(.peer(attemptID: id), as: .available)
        try await reservations.claimExclusive(
            .refund(operationID: "refund"),
            rawBalance: amount("100000000")
        )

        await #expect(throws: BaseUSDCReservationLedger.ClaimError.self) {
            try await runner.retry(id: id, rawBalance: amount("100000000"), sessionGeneration: 0)
        }
    }

    /// A decode/I/O failure is not evidence that the checkpoint book contained no attempts.
    @Test func unreadableHydrationFailsClosed() async {
        let reservations = BaseUSDCReservationLedger()
        await reservations.markReady(.scanAndPay)
        await reservations.markReady(.onrampDelivery)
        let runner = PeerCashOutRunner(reservations: reservations)

        await runner.hydrate(storedAttempts: { throw HydrationError.unreadable }, reconcileAfter: false)

        #expect(await runner.currentState.runs.isEmpty)
        #expect(await reservations.spendable(rawBalance: amount("100000000")) == .unavailable)
    }

    /// Cancellation is advisory: a foreign call can ignore it. Reset must join that call, and its
    /// old-generation result must be unable to stamp state after the wallet boundary moved.
    @Test func resetJoinsHydrationAndRejectsItsLateCompletion() async {
        let reservations = BaseUSDCReservationLedger()
        await reservations.markReady(.scanAndPay)
        await reservations.markReady(.onrampDelivery)
        let runner = PeerCashOutRunner(reservations: reservations)
        let release = TestContinuationGate()
        let started = AsyncStream<Void>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        let storedAttempt = attempt()

        var startedIterator = started.stream.makeAsyncIterator()
        var cancelledIterator = cancelled.stream.makeAsyncIterator()
        let hydration = Task {
            await runner.hydrate(storedAttempts: {
                started.continuation.yield()
                started.continuation.finish()
                return await withTaskCancellationHandler {
                    await release.wait()
                    return [storedAttempt]
                } onCancel: {
                    cancelled.continuation.yield()
                    cancelled.continuation.finish()
                }
            }, reconcileAfter: false)
        }
        _ = await startedIterator.next()

        let resetCompleted = LockIsolated(false)
        let reset = Task {
            await runner.reset()
            resetCompleted.setValue(true)
        }
        _ = await cancelledIterator.next()
        #expect(!resetCompleted.value)

        await release.open()
        await reset.value
        await hydration.value

        #expect(resetCompleted.value)
        #expect(await runner.currentState.runs.isEmpty)
        #expect(await reservations.spendable(rawBalance: amount("100000000")) == .unavailable)
    }

    private func readyRunner(
        _ reservations: BaseUSDCReservationLedger = BaseUSDCReservationLedger()
    ) async -> PeerCashOutRunner {
        for source in BaseUSDCReservationLedger.Source.allCases {
            await reservations.markReady(source)
        }
        return PeerCashOutRunner(reservations: reservations)
    }

    private func amount(_ micros: String) -> UsdcAmount {
        UsdcAmount(micros: micros) ?? .zero
    }

    private func attempt() -> PeerAttempt {
        PeerAttempt(
            id: "stored-attempt",
            destinationCode: "revolut",
            currencyCodes: ["EUR"],
            amount: amount("20000000"),
            createdAt: .distantPast,
            depositID: nil,
            holdsUnescrowedFunds: true
        )
    }

    private func failure(nothingEscrowed: Bool) -> PeerProgress {
        PeerProgress(
            subjectID: "attempt",
            kind: .failed,
            step: .creatingDeposit,
            amount: nil,
            txHash: nil,
            depositID: nil,
            order: nil,
            failure: PeerFailure(
                code: "RECOVERY_STATE_UNREADABLE",
                step: .creatingDeposit,
                allowsManualRetry: false,
                nothingEscrowed: nothingEscrowed,
                recovery: nil,
                escrowRevertBucket: nil
            ),
            isTerminal: true
        )
    }

    private func draft(amount: String) -> PeerCashOutDraft {
        PeerCashOutDraft(
            destinationCode: "revolut",
            handle: "somerevtag",
            currencyCodes: ["EUR"],
            amount: UsdcAmount(micros: amount) ?? .zero
        )
    }
}

private enum HydrationError: Error {
    case unreadable
}

private actor TestContinuationGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
