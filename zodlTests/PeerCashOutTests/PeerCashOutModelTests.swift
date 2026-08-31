// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

/// The value types the Peer money path is decided on. Each of these is a way an amount could be
/// misread, and every one of them spends the user's USDC twice or hides funds they still have.
struct UsdcAmountTests {
    @Test func microStringsRoundTripWithoutLosingPrecision() throws {
        let amount = try #require(UsdcAmount(micros: "20500000"))

        #expect(amount.microsString == "20500000")
        #expect(amount.whole == Decimal(string: "20.5"))
    }

    /// A read that could not be parsed and a balance of nothing are different answers, and only one
    /// of them permits a cash-out.
    @Test(arguments: ["", "abc", "-1", "1.5", "1e6", "1 000", "+1"])
    func unparseableMicrosAreNilRatherThanZero(value: String) {
        #expect(UsdcAmount(micros: value) == nil)
    }

    /// Truncating rather than rounding, so the amount escrowed is never more than was typed.
    @Test func typedAmountsTruncateBelowAMicro() throws {
        #expect(try #require(UsdcAmount(whole: "20.0000004")).microsString == "20000000")
        #expect(try #require(UsdcAmount(whole: "20.0000006")).microsString == "20000000")
        #expect(try #require(UsdcAmount(whole: "0.000001")).microsString == "1")
    }

    @Test func subtractionNeverGoesNegative() throws {
        let small = try #require(UsdcAmount(micros: "1"))
        let large = try #require(UsdcAmount(micros: "1000000"))

        #expect(small.subtractingClampedToZero(large) == .zero)
        #expect(large.subtractingClampedToZero(small).microsString == "999999")
    }

    @Test func displayStripsTheTrailingZerosAMicroUnitCarries() throws {
        #expect(try #require(UsdcAmount(micros: "20000000")).display == "20")
        #expect(try #require(UsdcAmount(micros: "20500000")).display == "20.5")
    }
}

/// The stored selection has to survive the upgrade that introduced Peer. Resetting it would send a
/// user who had chosen a corridor back to the default one without telling them.
struct P2pRailTests {
    @Test func aBareCurrencyCodeReadsAsTheScanAndPayRailItAlwaysWas() throws {
        let rail = try #require(P2pRail(id: "BRL"))

        #expect(rail == .scanAndPay(currencyCode: "BRL"))
        #expect(rail.provider == .p2pMe)
        // Rewritten in the new form the next time it is saved.
        #expect(rail.id == "p2pme:BRL")
    }

    @Test func prefixedIdsRoundTrip() throws {
        for rail in [P2pRail.scanAndPay(currencyCode: "INR"), .peerCashOut(destinationCode: "revolut")] {
            #expect(try #require(P2pRail(id: rail.id)) == rail)
        }
    }

    /// Buying runs over the p2p.me corridors only, so a Peer selection must resolve to one the
    /// on-ramp can actually serve rather than to a destination code it has never heard of.
    @Test func aPeerSelectionFallsBackForFlowsOnlyScanAndPayCanServe() {
        let peer = P2pRail.peerCashOut(destinationCode: "monzo")

        #expect(peer.provider == .peer)
        #expect(peer.scanAndPayCurrencyCode == P2pRail.default.scanAndPayCurrencyCode)
    }

    @Test func anEmptyStoredValueIsNoSelection() {
        #expect(P2pRail(id: "") == nil)
    }
}

struct PeerSpendableBalanceTests {
    /// An amount is not gone from the account until `createDeposit` is mined, so the raw balance
    /// still counts it and three consecutive orders would each spend the same coins.
    @Test func committedAttemptsAreSubtractedFromWhatCanBeOffered() throws {
        let balance = try #require(UsdcAmount(micros: "100000000"))
        let committed = try #require(UsdcAmount(micros: "40000000"))
        let spendable = PeerSpendableBalance.ready(balance: balance, committed: committed)

        #expect(spendable.available?.microsString == "60000000")
        #expect(spendable.covers(try #require(UsdcAmount(micros: "60000000"))))
        #expect(!spendable.covers(try #require(UsdcAmount(micros: "60000001"))))
    }

    /// A balance that could not be read blocks rather than waving through.
    @Test(arguments: [PeerSpendableBalance.loading, .unavailable])
    func anUnreadBalanceCoversNothing(spendable: PeerSpendableBalance) throws {
        #expect(spendable.available == nil)
        #expect(!spendable.covers(try #require(UsdcAmount(micros: "1"))))
    }

    /// Only surfaced when there is something to explain; zero would read as a deduction that isn't.
    @Test func noCommitmentIsNotReported() throws {
        let ready = PeerSpendableBalance.ready(balance: try #require(UsdcAmount(micros: "1")), committed: .zero)

        #expect(ready.committed == nil)
    }
}

/// Whether an attempt still has a claim on the smart account's USDC. Releasing one that does is how
/// the same coins get spent twice; holding one that does not hides funds the user still has.
struct PeerRunHoldsFundsTests {
    @Test func anAttemptWithNoOutcomeYetHoldsItsAmount() {
        #expect(run(statuses: [progress(.creatingDeposit)]).holdsFunds)
        #expect(run(statuses: []).holdsFunds)
    }

    @Test func anIndexedOrderReleasesTheReservationTheEscrowNowHolds() {
        #expect(!run(statuses: [progress(.orderLive, depositID: "escrow_1")]).holdsFunds)
    }

    /// A reconciliation is the only thing that can finish an attempt whose submission outcome was
    /// never known: it carries no status naming a deposit, so without this its amount stays
    /// reserved alongside the order it turned out to open.
    @Test func aReconciledAttemptReleasesEvenWithoutAStatusNamingTheDeposit() {
        var reconciled = run(statuses: [progress(.creatingDeposit), failure(nothingEscrowed: false)])
        #expect(reconciled.holdsFunds)

        reconciled.reconciledDepositID = "escrow_1"
        #expect(!reconciled.holdsFunds)
        // Still owed a row until the order list catches up: the deposit id comes from a receipt,
        // which is ahead of the indexer.
        #expect(reconciled.isAwaitingIndex(in: []))
        #expect(!reconciled.isAwaitingIndex(in: ["escrow_1"]))
    }

    /// A send that provably reverted escrowed nothing, so the amount goes back to the balance.
    @Test func aProvablyRevertedSendReleasesItsAmount() {
        #expect(!run(statuses: [progress(.creatingDeposit), failure(nothingEscrowed: true)]).holdsFunds)
    }

    /// An outcome nobody can name settles nothing, so the reservation survives.
    @Test func anUnknownOutcomeKeepsTheAmountReserved() {
        #expect(run(statuses: [progress(.creatingDeposit), failure(nothingEscrowed: false)]).holdsFunds)
    }

    /// A failure before `createDeposit` was ever attempted proves the USDC never left the account,
    /// so the reservation is released and the amount is offerable again immediately. Holding it
    /// would strand the balance behind an attempt that provably did nothing.
    @Test func aFailureBeforeAnySendReleasesTheReservation() {
        #expect(!run(statuses: [progress(.validatingPayee), failure(nothingEscrowed: true)]).holdsFunds)
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

    private func progress(_ kind: PeerProgress.Kind, depositID: String? = nil) -> PeerProgress {
        PeerProgress(
            subjectID: "0123456789abcdef0123456789abcdef",
            kind: kind,
            step: .creatingDeposit,
            amount: nil,
            txHash: nil,
            depositID: depositID,
            order: nil,
            failure: nil,
            isTerminal: false
        )
    }

    private func failure(nothingEscrowed: Bool) -> PeerProgress {
        PeerProgress(
            subjectID: "0123456789abcdef0123456789abcdef",
            kind: .failed,
            step: .creatingDeposit,
            amount: nil,
            txHash: nil,
            depositID: nil,
            order: nil,
            failure: PeerFailure(
                code: nothingEscrowed ? "TRANSACTION_FAILED" : "TRANSACTION_SUBMISSION_UNKNOWN",
                step: .creatingDeposit,
                allowsManualRetry: nothingEscrowed,
                nothingEscrowed: nothingEscrowed,
                recovery: nil,
                escrowRevertBucket: nil
            ),
            isTerminal: true
        )
    }
}
