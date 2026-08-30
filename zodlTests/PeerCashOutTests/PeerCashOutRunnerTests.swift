// SPDX-License-Identifier: MIT OR Apache-2.0

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
    @Test func startingAnAttemptReservesItsAmountImmediately() async {
        let runner = PeerCashOutRunner()
        let id = await runner.newAttemptID(byteCount: 16)

        let started = await runner.start(id: id, draft: draft(amount: "20000000"))

        #expect(started == id)
        let state = await runner.currentState
        #expect(state.runs.count == 1)
        #expect(state.committedByRuns.microsString == "20000000")
    }

    /// A repeat start on the same attempt must not rewind one already in flight.
    @Test func aRepeatStartIsDroppedRatherThanRestarting() async {
        let runner = PeerCashOutRunner()
        let id = await runner.newAttemptID(byteCount: 16)

        _ = await runner.start(id: id, draft: draft(amount: "20000000"))
        let second = await runner.start(id: id, draft: draft(amount: "50000000"))

        #expect(second == nil)
        let state = await runner.currentState
        #expect(state.runs.count == 1)
        #expect(state.committedByRuns.microsString == "20000000")
    }

    /// Several cash-outs can be unfinished at once, and each reserves its own amount.
    @Test func concurrentAttemptsEachReserveTheirOwnAmount() async {
        let runner = PeerCashOutRunner()
        let first = await runner.newAttemptID(byteCount: 16)
        let second = await runner.newAttemptID(byteCount: 16)

        _ = await runner.start(id: first, draft: draft(amount: "20000000"))
        _ = await runner.start(id: second, draft: draft(amount: "30000000"))

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
    @Test func resetClearsEveryReservation() async {
        let runner = PeerCashOutRunner()
        let id = await runner.newAttemptID(byteCount: 16)
        _ = await runner.start(id: id, draft: draft(amount: "20000000"))

        await runner.reset()

        let state = await runner.currentState
        #expect(state.runs.isEmpty)
        #expect(state.committedByRuns == .zero)
    }

    /// A screen that subscribes after the work started still needs to see it, so the current state
    /// is published on subscription rather than only on the next change.
    @Test func subscribingPublishesTheCurrentStateImmediately() async throws {
        let runner = PeerCashOutRunner()
        let id = await runner.newAttemptID(byteCount: 16)
        _ = await runner.start(id: id, draft: draft(amount: "20000000"))

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

    private func draft(amount: String) -> PeerCashOutDraft {
        PeerCashOutDraft(
            destinationCode: "revolut",
            handle: "somerevtag",
            currencyCodes: ["EUR"],
            amount: UsdcAmount(micros: amount) ?? .zero
        )
    }
}
