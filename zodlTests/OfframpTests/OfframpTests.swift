// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized)
struct OfframpTests {
    @MainActor
    @Test func resumeCheckpointUsesPersistedCorridor() async {
        var state = Offramp.State.initial()
        state.selectedCurrencyCode = "BRL"
        state.draftCurrencyCode = "BRL"
        state.hasCheckpoint = true
        state.checkpointCurrencyCode = "INR"
        let store = TestStore(initialState: state) { Offramp() }

        await store.send(.resumeCheckpointTapped) {
            $0.selectedCurrencyCode = "INR"
            $0.draftCurrencyCode = "INR"
            $0.isResumingCheckpoint = true
        }
    }

    @MainActor
    @Test func amountInputIsSanitizedAndInvalidatesQuote() async {
        var state = Offramp.State.initial(page: .amount)
        state.quote = quote()
        let store = TestStore(initialState: state) { Offramp() }

        await store.send(.fiatAmountChanged("1a2,3.4")) {
            $0.fiatAmount = "12.34"
            $0.quote = nil
        }
    }

    @MainActor
    @Test func repeatedProgressKindReplacesCurrentStep() async {
        var state = Offramp.State.initial(page: .progress)
        state.progress = [progress(title: "Waiting")]
        state.isLoading = true
        let updated = progress(title: "Still waiting", detail: "Merchant has 2 minutes remaining")
        let store = TestStore(initialState: state) { Offramp() }

        await store.send(.progressReceived(updated)) {
            $0.progress = [updated]
        }
    }

    @MainActor
    @Test func terminalProgressClearsCheckpointPresentation() async {
        var state = Offramp.State.initial(page: .progress)
        state.hasCheckpoint = true
        state.checkpointCurrencyCode = "INR"
        state.isResumingCheckpoint = true
        state.isLoading = true
        let completed = progress(kind: "completed", title: "Complete", isTerminal: true, isSuccess: true)
        let store = TestStore(initialState: state) { Offramp() }

        await store.send(.progressReceived(completed)) {
            $0.progress = [completed]
            $0.isLoading = false
            $0.hasCheckpoint = false
            $0.checkpointCurrencyCode = nil
            $0.isResumingCheckpoint = false
        }
    }

    @Test func bridgeQuoteValidatorAcceptsExactEcho() throws {
        try OfframpBridgeQuoteValidator.validate(
            bridgeQuote(),
            requestedMicros: "2500000",
            destinationAddress: "0xBase",
            refundAddress: "u1refund",
            originAssetId: "zec",
            destinationAssetId: "base-usdc"
        )
    }

    @Test func bridgeQuoteValidatorRejectsChangedDestination() {
        #expect(throws: OfframpBridgeError.self) {
            try OfframpBridgeQuoteValidator.validate(
                bridgeQuote(destinationAddress: "0xAttacker"),
                requestedMicros: "2500000",
                destinationAddress: "0xBase",
                refundAddress: "u1refund",
                originAssetId: "zec",
                destinationAssetId: "base-usdc"
            )
        }
    }

    @Test func bridgeQuoteValidatorRejectsChangedRefundAddress() {
        #expect(throws: OfframpBridgeError.self) {
            try OfframpBridgeQuoteValidator.validate(
                bridgeQuote(refundAddress: "u1attacker"),
                requestedMicros: "2500000",
                destinationAddress: "0xBase",
                refundAddress: "u1refund",
                originAssetId: "zec",
                destinationAssetId: "base-usdc"
            )
        }
    }

    @Test func refundQuoteValidatorAcceptsExactEcho() throws {
        try OfframpBridgeQuoteValidator.validateRefund(
            refundQuote(),
            requestedMicros: "2500000",
            destinationAddress: "u1destination",
            refundAddress: "0xBase",
            originAssetId: "base-usdc",
            destinationAssetId: "zec"
        )
    }

    @Test func refundQuoteValidatorRejectsChangedRoute() {
        #expect(throws: OfframpBridgeError.self) {
            try OfframpBridgeQuoteValidator.validateRefund(
                refundQuote(destinationAddress: "u1attacker"),
                requestedMicros: "2500000",
                destinationAddress: "u1destination",
                refundAddress: "0xBase",
                originAssetId: "base-usdc",
                destinationAssetId: "zec"
            )
        }
    }

    @Test func refundQuoteValidatorRejectsChangedAmount() {
        #expect(throws: OfframpBridgeError.self) {
            try OfframpBridgeQuoteValidator.validateRefund(
                refundQuote(amountIn: 2.6),
                requestedMicros: "2500000",
                destinationAddress: "u1destination",
                refundAddress: "0xBase",
                originAssetId: "base-usdc",
                destinationAssetId: "zec"
            )
        }
    }

    private func quote() -> OfframpQuoteModel {
        OfframpQuoteModel(
            currencyCode: "INR",
            fiatAmount: "100",
            usdcMicros: "1000000",
            usdcDisplay: "1",
            sellRate: "100",
            fixedFeeDisplay: "0.1",
            baseBalanceDisplay: "2",
            shortfallMicros: "0",
            shortfallDisplay: "0",
            canPayFromBase: true,
            canBridgeToBase: true
        )
    }

    private func progress(
        kind: String = "waiting_for_merchant",
        title: String,
        detail: String? = nil,
        isTerminal: Bool = false,
        isSuccess: Bool = false
    ) -> OfframpProgressModel {
        OfframpProgressModel(
            kind: kind,
            step: "WAITING_FOR_ACCEPTANCE",
            title: title,
            detail: detail,
            orderId: "7",
            txHash: nil,
            bridgeDepositAddress: nil,
            isTerminal: isTerminal,
            isSuccess: isSuccess
        )
    }

    private func bridgeQuote(
        destinationAddress: String = "0xBase",
        refundAddress: String = "u1refund"
    ) -> SwapQuote {
        SwapQuote(
            depositAddress: "u1deposit",
            destinationAddress: destinationAddress,
            refundAddress: refundAddress,
            originAssetId: "zec",
            destinationAssetId: "base-usdc",
            amountIn: 100_000_000,
            amountInUsd: "1",
            minAmountIn: 100_000_000,
            amountOut: 2.5,
            amountOutUsd: "2.5",
            timeEstimate: 60
        )
    }

    private func refundQuote(
        destinationAddress: String = "u1destination",
        amountIn: Decimal = 2.5
    ) -> SwapQuote {
        SwapQuote(
            depositAddress: "0xdeposit",
            destinationAddress: destinationAddress,
            refundAddress: "0xBase",
            originAssetId: "base-usdc",
            destinationAssetId: "zec",
            amountIn: amountIn,
            amountInUsd: "2.5",
            minAmountIn: 0.1,
            amountOut: 100_000_000,
            amountOutUsd: "2.5",
            timeEstimate: 60
        )
    }
}
