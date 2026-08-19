import Foundation
import Testing
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite
struct GetBalanceHistoryUseCaseTests {
    @Test
    func settledDeltasReconcileToConfirmedBalance() throws {
        let history = reconcileBalanceHistory(
            transactions: [transaction("receive", .received, 100, 1), transaction("send", .paid, 25, 2)],
            confirmedBalance: Zatoshi(75)
        )
        guard case .reconciled(let points, let balance) = history else {
            Issue.record("Expected reconciled history")
            return
        }
        #expect(points.map { $0.balance.amount } == [100, 75])
        #expect(balance.amount == 75)
    }

    @Test
    func negativeRunningBalanceIsInconsistent() {
        #expect(reconcileBalanceHistory(
            transactions: [transaction("send", .paid, 1, 1)],
            confirmedBalance: .zero
        ) == .inconsistent)
    }

    @Test
    func settledNonZeroDeltaWithoutBlockTimeIsInconsistent() {
        #expect(reconcileBalanceHistory(
            transactions: [transaction("receive", .received, 1, nil)],
            confirmedBalance: Zatoshi(1)
        ) == .inconsistent)
    }

    @Test
    func settledZeroDeltaWithoutBlockTimeIsIgnored() {
        #expect(reconcileBalanceHistory(
            transactions: [transaction("zero", .shielded, 0, nil)],
            confirmedBalance: .zero
        ) == .reconciled(points: [], confirmedBalance: .zero))
    }

    @Test
    func groupedDeltaOverflowIsInconsistent() {
        #expect(reconcileBalanceHistory(
            transactions: [
                transaction("first", .received, .max, 1),
                transaction("second", .received, 1, 1)
            ],
            confirmedBalance: .zero
        ) == .inconsistent)
    }

    @Test
    func finalBalanceMismatchIsInconsistent() {
        #expect(reconcileBalanceHistory(
            transactions: [transaction("receive", .received, 1, 1)],
            confirmedBalance: Zatoshi(2)
        ) == .inconsistent)
    }

    @Test
    func pendingTransactionsDoNotAffectHistory() {
        let history = reconcileBalanceHistory(
            transactions: [
                transaction("confirmed", .received, 2, 1),
                transaction("pending", .receiving, 9, nil)
            ],
            confirmedBalance: Zatoshi(2)
        )
        guard case .reconciled(let points, _) = history else {
            Issue.record("Expected reconciled history")
            return
        }
        #expect(points.map { $0.balance.amount } == [2])
    }

    @Test
    func settledShieldingUsesItsNetFeeAsAWithdrawal() {
        let history = reconcileBalanceHistory(
            transactions: [
                transaction("receive", .received, 100, 1),
                transaction("shield", .shielded, 2, 2, isSent: true)
            ],
            confirmedBalance: Zatoshi(98)
        )
        guard case .reconciled(let points, _) = history else {
            Issue.record("Expected reconciled history")
            return
        }
        #expect(points.map { $0.balance.amount } == [100, 98])
    }

    /// `amount` is a magnitude. The fixture negates outgoing rows because that is what the app
    /// stores: `TransactionState.init(transaction:)` writes `Zatoshi(-value)` for a send. A fixture
    /// that keeps sends positive passes against reconciliation logic no real wallet ever feeds.
    /// Pins the convention the production initializer actually produces. The SDK's
    /// `Overview.value` is a signed balance delta — `isSentTransaction` is defined as `value < 0` —
    /// and `TransactionState.init(transaction:)` negates it, so a completed send reaches
    /// reconciliation as a POSITIVE magnitude carrying `isSentTransaction`. A fixture that stored
    /// sends negative would pass against logic no real wallet ever feeds.
    @Test
    func completedSendStoredAsAMagnitudeReconciles() {
        let received = TransactionState(
            fee: nil,
            id: "receive",
            status: .received,
            timestamp: 1,
            zecAmount: Zatoshi(100),
            isSentTransaction: false
        )
        let sent = TransactionState(
            fee: nil,
            id: "send",
            status: .paid,
            timestamp: 2,
            zecAmount: Zatoshi(25),
            isSentTransaction: true
        )
        #expect(
            reconcileBalanceHistory(transactions: [received, sent], confirmedBalance: Zatoshi(75))
                == .reconciled(
                    points: [
                        .init(timestamp: Date(timeIntervalSince1970: 1), balance: Zatoshi(100)),
                        .init(timestamp: Date(timeIntervalSince1970: 2), balance: Zatoshi(75))
                    ],
                    confirmedBalance: Zatoshi(75)
                )
        )
    }

    @Test
    func negativeMagnitudeIsInconsistent() {
        let malformed = TransactionState(
            fee: nil,
            id: "send",
            status: .paid,
            timestamp: 1,
            zecAmount: Zatoshi(-25),
            isSentTransaction: true
        )
        #expect(reconcileBalanceHistory(transactions: [malformed], confirmedBalance: .zero) == .inconsistent)
    }

    private func transaction(
        _ id: String,
        _ status: TransactionState.Status,
        _ amount: Int64,
        _ timestamp: TimeInterval?,
        isSent: Bool? = nil
    ) -> TransactionState {
        TransactionState(
            fee: nil,
            id: id,
            status: status,
            timestamp: timestamp,
            zecAmount: Zatoshi(amount),
            isSentTransaction: isSent ?? (status == .paid)
        )
    }
}
