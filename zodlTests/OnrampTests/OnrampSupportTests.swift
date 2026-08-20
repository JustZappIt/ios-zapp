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
}
