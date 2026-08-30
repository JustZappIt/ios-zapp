// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

/// The gate between what the user typed and an irreversible escrow.
struct PeerCashOutFormTests {
    @Test func anAmountBelowTheRecommendedFloorIsRefused() throws {
        var state = form(available: "100000000")
        state.amountInput = "19"

        #expect(state.amountError != nil)
        #expect(!state.canSubmit)
    }

    /// The floor is the recommended one, not the protocol's: below it the order goes dark in the
    /// orderbook the moment it sells part-way down.
    @Test func theRecommendedMinimumIsAccepted() throws {
        var state = form(available: "100000000")
        state.amountInput = "20"

        #expect(state.amountError == nil)
        #expect(state.canSubmit)
    }

    /// Over the spendable balance is an inline stop, never a silent ZEC bridge.
    @Test func anAmountOverWhatIsSpendableIsRefusedRatherThanBridged() throws {
        var state = form(available: "100000000", committed: "60000000")
        state.amountInput = "50"

        #expect(state.amountError != nil)
        #expect(!state.canSubmit)

        state.amountInput = "40"
        #expect(state.amountError == nil)
        #expect(state.canSubmit)
    }

    @Test func anUnreadableBalanceBlocksRatherThanWavingThrough() throws {
        var state = form(available: nil)
        state.amountInput = "20"

        #expect(state.amountError != nil)
        #expect(!state.canSubmit)
    }

    /// A handle the rail's rules reject never reaches the curator, and never enables the button.
    @Test func aHandleThatFailsFormatRulesBlocksSubmission() throws {
        var state = form(available: "100000000")
        state.amountInput = "20"
        state.handleCheck = PeerHandleCheck(normalized: nil, changedWhatWasTyped: false, validatesLive: true)

        #expect(state.handleError != nil)
        #expect(!state.canSubmit)
    }

    /// A buyer pays exactly what was registered, so a normalization the user did not type is shown.
    @Test func normalizingIsEchoedOnlyWhenItChangedWhatWasTyped() {
        var state = form(available: "100000000")
        state.handleInput = "handle"
        state.handleCheck = PeerHandleCheck(normalized: "$handle", changedWhatWasTyped: true, validatesLive: false)
        #expect(state.normalizedEcho != nil)

        state.handleCheck = PeerHandleCheck(normalized: "handle", changedWhatWasTyped: false, validatesLive: false)
        #expect(state.normalizedEcho == nil)
    }

    /// Zelle and Chime cannot be checked with the platform, so the user is warned rather than
    /// reassured by a validation that never ran.
    @Test func anUncheckableRailWarnsInsteadOfReassuring() {
        var state = form(available: "100000000")
        state.handleCheck = PeerHandleCheck(normalized: "someone@example.com", changedWhatWasTyped: false, validatesLive: false)
        #expect(state.showsUnverifiedHandleWarning)

        state.handleCheck = PeerHandleCheck(normalized: "revtag", changedWhatWasTyped: false, validatesLive: true)
        #expect(!state.showsUnverifiedHandleWarning)
    }

    /// Removing the last currency would leave a deposit no buyer can fill.
    @Test func theLastCurrencyCannotBeRemoved() {
        var state = form(available: "100000000")
        state.selectedCurrencyCodes = ["EUR", "GBP"]

        state.toggleCurrency("GBP")
        #expect(state.selectedCurrencyCodes == ["EUR"])

        state.toggleCurrency("EUR")
        #expect(state.selectedCurrencyCodes == ["EUR"])
    }

    /// The first is the primary — the currency the rate is quoted in — so removing it promotes the
    /// next rather than leaving the rate labelled with a currency the order no longer offers.
    @Test func removingThePrimaryPromotesTheNextOne() {
        var state = form(available: "100000000")
        state.selectedCurrencyCodes = ["EUR", "GBP", "USD"]

        state.toggleCurrency("EUR")

        #expect(state.primaryCurrencyCode == "GBP")
        #expect(state.selectedCurrencyCodes == ["GBP", "USD"])
    }

    /// A rail with one currency has nothing to choose, and a stray tap must not empty it.
    @Test func aSingleCurrencyRailIgnoresToggles() {
        var state = form(available: "100000000", offersCurrencyChoice: false)
        state.selectedCurrencyCodes = ["USD"]

        state.toggleCurrency("USD")
        state.toggleCurrency("EUR")

        #expect(state.selectedCurrencyCodes == ["USD"])
    }

    /// Topping up is its own screen with its own authentication; the form only routes to it.
    @Test func topUpIsAnExplicitRouteAndNeverStartsOnItsOwn() async {
        let store = await TestStore(initialState: form(available: "100000000")) { PeerCashOutForm() }

        await store.send(.topUpTapped)
        await store.receive(\.delegate.topUp)
    }

    @Test func startingACashOutHandsTheAttemptToTheRunnerAndOpensIt() async {
        var state = form(available: "100000000")
        state.amountInput = "20"

        let started = LockIsolated<PeerCashOutDraft?>(nil)
        let store = await TestStore(initialState: state) { PeerCashOutForm() } withDependencies: {
            $0.peerCashOut.startCashOut = { draft in
                started.setValue(draft)
                return "0123456789abcdef0123456789abcdef"
            }
        }

        await store.send(.continueTapped) { $0.isSubmitting = true }
        await store.receive(\.started) {
            $0.isSubmitting = false
            $0.amountInput = ""
        }
        await store.receive(\.delegate.openAttempt)

        let draft = started.value
        #expect(draft?.amount.microsString == "20000000")
        #expect(draft?.handle == "somerevtag")
        #expect(draft?.currencyCodes == ["EUR"])
    }

    private func form(
        available: String?,
        committed: String = "0",
        offersCurrencyChoice: Bool = true
    ) -> PeerCashOutForm.State {
        var state = PeerCashOutForm.State(destinationCode: "revolut")
        state.recommendedMinimum = UsdcAmount(micros: "20000000") ?? .zero
        state.destination = PeerDestination(
            code: "revolut",
            currencies: [
                PeerFiatCurrency(code: "EUR", symbol: "€", precision: 2),
                PeerFiatCurrency(code: "GBP", symbol: "£", precision: 2),
                PeerFiatCurrency(code: "USD", symbol: "$", precision: 2)
            ],
            defaultCurrencyCodes: ["EUR"],
            validatesHandleLive: true,
            offersCurrencyChoice: offersCurrencyChoice
        )
        state.selectedCurrencyCodes = ["EUR"]
        state.handleInput = "somerevtag"
        state.handleCheck = PeerHandleCheck(normalized: "somerevtag", changedWhatWasTyped: false, validatesLive: true)
        state.spendable = available.flatMap { UsdcAmount(micros: $0) }.map {
            .ready(balance: $0, committed: UsdcAmount(micros: committed) ?? .zero)
        } ?? .unavailable
        return state
    }
}
