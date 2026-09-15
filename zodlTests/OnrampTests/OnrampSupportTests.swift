// SPDX-License-Identifier: MIT OR Apache-2.0

import Testing
@testable import zodl_internal

struct OnrampSupportTests {
    @Test func fiatAmountConvertsToMicrosWithoutRoundingUp() {
        #expect(Onramp.fiatMicros("12.3456789") == "12345678")
        #expect(Onramp.fiatMicros("0") == nil)
        #expect(Onramp.fiatMicros("") == nil)
    }

    @Test func zcashIsTheDefaultDestination() {
        let state = Onramp.State.initial(currencyCode: "INR")

        #expect(state.destination == .zcash)
        #expect(state.isZecDestinationEnabled)
        #expect(state.currencyCode == "INR")
    }

    @Test func baseRefundRequiresProvablyAvailableBalance() {
        let account = OfframpAccountModel(
            address: "0x1234",
            balanceMicros: "1200000",
            balanceDisplay: "1.2 USDC",
            explorerURL: nil,
            canBridgeToBase: false,
            canRefundToZec: true
        )
        let blocked = OfframpAccountModel(
            address: account.address,
            balanceMicros: account.balanceMicros,
            balanceDisplay: account.balanceDisplay,
            explorerURL: nil,
            canBridgeToBase: false,
            canRefundToZec: false
        )

        #expect(Onramp.baseRefundState(account) == .available)
        #expect(Onramp.baseRefundState(blocked) == .blocked)
        #expect(Onramp.baseRefundState(nil) == .hidden)
    }

    @Test func everyDirectRouteFailureHasItsOwnSentence() {
        // The rolling caps must not read as "try a smaller amount": nothing passes until the
        // window rolls over, and a blocked wallet must not be told to verify.
        #expect(Onramp.failureMessage(.dailyLimitExceeded) == String(localizable: .onrampErrorDailyLimit))
        #expect(Onramp.failureMessage(.volumeLimitExceeded) == String(localizable: .onrampErrorVolumeLimit))
        #expect(Onramp.failureMessage(.userBlocked) == String(localizable: .onrampErrorUserBlocked))
        #expect(Onramp.failureMessage(.settlementPending) == String(localizable: .onrampErrorSettlementPending))
        #expect(Onramp.failureMessage(.capExceeded) != Onramp.failureMessage(.dailyLimitExceeded))
    }

    @Test func aPendingSettlementLeavesTheOrderAlive() {
        // Fiat has left the user's account; dropping the checkpoint here would strand it.
        #expect(OnrampFailureCodeModel.settlementPending.leavesOrderAlive)
        #expect(!OnrampFailureCodeModel.dailyLimitExceeded.leavesOrderAlive)
        #expect(!OnrampFailureCodeModel.userBlocked.leavesOrderAlive)
    }

    @Test func theServicesOwnSentenceWinsWhenItGaveOne() {
        let refused = status(code: .screeningRejected, detail: "  new accounts cannot place buy orders at this time \n")
        #expect(Onramp.failureMessage(refused) == "new accounts cannot place buy orders at this time")

        let blank = status(code: .screeningRejected, detail: "   ")
        #expect(Onramp.failureMessage(blank) == String(localizable: .onrampErrorScreeningRejected))
        #expect(Onramp.failureMessage(status(code: .noMerchant, detail: nil)) == String(localizable: .onrampErrorNoMerchant))

        let long = status(code: .screeningRejected, detail: String(repeating: "x", count: 500))
        #expect(Onramp.failureMessage(long).count == Onramp.serviceDetailMaxCharacters)
    }

    @Test func theLimitRowFollowsWhatTheRailReports() {
        // The direct rail reports no daily figure, so the per-order ceiling is the row; a rail
        // that reports one shows that instead of a per-order figure.
        var state = Onramp.State.initial(currencyCode: "INR")
        state.limits = limits(maximum: "2035400000", daily: "0")
        #expect(state.transactionLimitMicros == "2035400000")
        #expect(state.dailyLimitMicros == nil)

        state.limits = limits(maximum: "2035400000", daily: "5000000000")
        #expect(state.transactionLimitMicros == nil)
        #expect(state.dailyLimitMicros == "5000000000")

        state.limits = nil
        #expect(state.transactionLimitMicros == nil)
        #expect(state.dailyLimitMicros == nil)
        #expect(Onramp.isZeroMicros("garbage"))
    }

    private func limits(maximum: String, daily: String) -> OnrampLimitsModel {
        OnrampLimitsModel(
            enabled: true,
            currencyCode: "INR",
            minimumFiatMicros: "106860000",
            maximumFiatMicros: maximum,
            dailyFiatMicros: daily
        )
    }

    private func status(code: OnrampFailureCodeModel, detail: String?) -> OnrampStatusModel {
        OnrampStatusModel(
            kind: .failed,
            phase: .placing,
            id: nil,
            orderID: nil,
            failureCode: code,
            failureDetail: detail,
            instruction: nil,
            fiatMicros: nil,
            netUsdcMicros: nil,
            recipientAddress: nil,
            paidTransactionHash: nil,
            expiresAt: nil,
            isTerminal: true
        )
    }
}
