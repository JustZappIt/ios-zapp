// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

/// The progress list is what a user reads to decide whether their money is safe, so a row that
/// claims the wrong thing is a real cost: a permanently pending row reads as something left undone,
/// and a "waiting for a buyer" row on a sold-out order reads as an order that never filled.
struct PeerProgressStepsTests {
    /// A cash-out spends Base USDC the user already has, so there is no funding step to show unless
    /// funding is what failed.
    @Test func fundingIsHiddenUnlessItIsWhatFailed() {
        let normal = PeerProgressSteps.build(from: run(statuses: [status(.approvingUsdc, step: .approvingUsdc)]))
        #expect(!normal.contains { $0.id == PeerProgress.Step.funding.rawValue })

        let failed = PeerProgressSteps.build(from: run(statuses: [failure(at: .funding)]))
        #expect(failed.contains { $0.id == PeerProgress.Step.funding.rawValue })
    }

    /// An order that fills completely never withdraws, and a pending withdrawal row would read as
    /// money still owed to the user.
    @Test func withdrawalIsHiddenUntilAnUnwindIsUnderWay() {
        let waiting = PeerProgressSteps.build(from: run(statuses: [status(.orderLive, step: .awaitingBuyer)]))
        #expect(!waiting.contains { $0.id == PeerProgress.Step.withdrawing.rawValue })

        let unwinding = PeerProgressSteps.build(from: run(statuses: [status(.withdrawing, step: .withdrawing)]))
        #expect(unwinding.contains { $0.id == PeerProgress.Step.withdrawing.rawValue })
    }

    @Test func theStepReachedIsInProgressAndEverythingBeforeItIsDone() throws {
        let steps = PeerProgressSteps.build(from: run(statuses: [status(.creatingDeposit, step: .creatingDeposit)]))
        let creating = try #require(steps.firstIndex { $0.id == PeerProgress.Step.creatingDeposit.rawValue })

        #expect(steps[creating].status == .inProgress)
        #expect(steps[..<creating].allSatisfy { $0.status == .completed })
        #expect(steps[(creating + 1)...].allSatisfy { $0.status == .pending })
    }

    @Test func aFailedStepIsMarkedFailedRatherThanInProgress() throws {
        let steps = PeerProgressSteps.build(from: run(statuses: [failure(at: .creatingDeposit)]))
        let creating = try #require(steps.first { $0.id == PeerProgress.Step.creatingDeposit.rawValue })

        #expect(creating.status == .failed)
    }

    /// A hidden step resolves forward to the next visible row, so everything before it still reads
    /// as done rather than the whole list resetting to pending.
    @Test func aStepWithNoRowOfItsOwnStillAdvancesTheOnesBeforeIt() throws {
        let steps = PeerProgressSteps.build(from: run(statuses: [status(.funded, step: .funding)]))
        let validating = try #require(steps.first { $0.id == PeerProgress.Step.validatingPayee.rawValue })
        let approving = try #require(steps.first { $0.id == PeerProgress.Step.approvingUsdc.rawValue })

        #expect(validating.status == .completed)
        #expect(approving.status == .inProgress)
    }

    /// The waiting row would otherwise still say "waiting for a buyer" after the whole order sold.
    @Test func aSoldOutOrderMarksEveryRowDone() {
        let steps = PeerProgressSteps.build(from: run(statuses: [status(.orderLive, step: .awaitingBuyer, order: order(phase: .sold))]))

        #expect(!steps.isEmpty)
        #expect(steps.allSatisfy { $0.status == .completed })
    }

    @Test func aPartialFillIsReportedAgainstWhatTheOrderWasFundedWith() throws {
        let partial = order(phase: .partlySold, sold: "5000000", gross: "20000000")
        let steps = PeerProgressSteps.build(from: run(statuses: [status(.orderLive, step: .awaitingBuyer, order: partial)]))
        let waiting = try #require(steps.first { $0.id == PeerProgress.Step.awaitingBuyer.rawValue })

        let detail = try #require(waiting.detail)
        #expect(detail.contains("5"))
        #expect(detail.contains("20"))
    }

    @Test func anAttemptWithNoStatusYetShowsEverythingAsPending() {
        let steps = PeerProgressSteps.build(from: nil)

        #expect(!steps.isEmpty)
        #expect(steps.allSatisfy { $0.status == .pending })
    }

    private func run(statuses: [PeerProgress]) -> PeerRun {
        PeerRun(
            id: "0123456789abcdef0123456789abcdef",
            destinationCode: "revolut",
            amount: UsdcAmount(micros: "20000000") ?? .zero,
            currencyCodes: ["EUR"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            statuses: statuses
        )
    }

    private func status(
        _ kind: PeerProgress.Kind,
        step: PeerProgress.Step,
        order: PeerOrder? = nil
    ) -> PeerProgress {
        PeerProgress(
            subjectID: "0123456789abcdef0123456789abcdef",
            kind: kind,
            step: step,
            amount: nil,
            txHash: nil,
            depositID: order?.depositID,
            order: order,
            failure: nil,
            isTerminal: false
        )
    }

    private func failure(at step: PeerProgress.Step) -> PeerProgress {
        PeerProgress(
            subjectID: "0123456789abcdef0123456789abcdef",
            kind: .failed,
            step: step,
            amount: nil,
            txHash: nil,
            depositID: nil,
            order: nil,
            failure: PeerFailure(
                code: "TRANSACTION_FAILED",
                step: step,
                retryable: false,
                allowsManualRetry: true,
                nothingEscrowed: true,
                recovery: nil,
                escrowRevertBucket: nil
            ),
            isTerminal: true
        )
    }

    private func order(phase: PeerOrder.Phase, sold: String = "0", gross: String = "20000000") -> PeerOrder {
        PeerOrder(
            depositID: "0x777777779d229cdf3110e9de47943791c26300ef_1",
            phase: phase,
            isFinished: phase == .sold || phase == .closed,
            acceptingIntents: true,
            gross: UsdcAmount(micros: gross) ?? .zero,
            remaining: .zero,
            sold: UsdcAmount(micros: sold) ?? .zero,
            locked: .zero,
            withdrawn: .zero,
            withdrawable: .zero,
            destinationCode: "revolut",
            currencyCodes: ["EUR"],
            buyerLegs: [],
            offersWithdrawal: false,
            offersMatchingToggle: false,
            isHiddenFromBuyers: false,
            openedAt: nil,
            lastActivityAt: nil,
            explorerURL: nil
        )
    }
}
