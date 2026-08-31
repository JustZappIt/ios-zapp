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
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.resumePayment = { AsyncStream { $0.finish() } }
            $0.offramp.checkpointCurrencyCode = { nil }
            $0.offramp.topUpCheckpointMicros = { nil }
        }

        await store.send(.resumeCheckpointTapped) {
            $0.selectedCurrencyCode = "INR"
            $0.draftCurrencyCode = "INR"
            $0.isResumingCheckpoint = true
            $0.page = .progress
            $0.isLoading = true
        }
        await store.receive(\.progressFinished) { $0.isLoading = false }
        await store.receive(\.checkpointsLoaded) {
            $0.hasCheckpoint = false
            $0.checkpointCurrencyCode = nil
        }
    }

    @MainActor
    @Test func paymentMethodSelectionReturnsToAmount() async {
        var state = Offramp.State.initial(page: .amount, corridorContext: .payment)
        state.corridors = [corridor("INR"), corridor("BRL")]
        state.selectedCurrencyCode = "INR"
        state.draftCurrencyCode = "INR"
        let store = TestStore(initialState: state) { Offramp() }

        await store.send(.chooseCorridorTapped) {
            $0.corridorContext = .payment
            $0.page = .corridors
        }
        await store.send(.draftCorridorTapped("BRL")) { $0.draftCurrencyCode = "BRL" }
        await store.send(.saveCorridorTapped) {
            $0.selectedCurrencyCode = "BRL"
            $0.page = .amount
        }
    }

    @MainActor
    @Test func addFundsIsAvailableBeforeQuote() async {
        var state = Offramp.State.initial(page: .amount, corridorContext: .payment)
        state.account = account()
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.accountSummary = { self.account() }
        }

        await store.send(.addFundsTapped) {
            $0.page = .topUp
            $0.isLoading = true
        }
        await store.receive(\.accountLoaded) { $0.isLoading = false }
    }

    @MainActor
    @Test func merchantAcceptanceOpensScannerAfterOrderStarts() async {
        var state = Offramp.State.initial(page: .amount, corridorContext: .payment)
        state.quote = quote()
        let waiting = progress(kind: "waiting_for_payment_details", title: "Merchant accepted")
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.quote = { _, _ in self.quote() }
            $0.offramp.pay = { _, _ in
                AsyncStream {
                    $0.yield(waiting)
                    $0.finish()
                }
            }
            $0.offramp.checkpointCurrencyCode = { nil }
            $0.offramp.topUpCheckpointMicros = { nil }
        }

        await store.send(.payTapped) {
            $0.isLoading = true
        }
        await store.receive(\.payQuoteRefreshed) {
            $0.isLoading = false
        }
        await store.receive(\.payConfirmed) {
            $0.page = .progress
            $0.isLoading = true
        }
        await store.receive(\.progressReceived) {
            $0.progress = [waiting]
            $0.page = .scanner
            $0.isLoading = false
        }
        await store.receive(\.progressFinished)
        await store.receive(\.checkpointsLoaded)
    }

    @MainActor
    @Test func changedCommitTimeQuoteRequiresExplicitConfirmation() async {
        var state = Offramp.State.initial(page: .amount, corridorContext: .payment)
        state.quote = quote()
        let refreshed = quote(usdcMicros: "1100000")
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.quote = { _, _ in refreshed }
        }

        await store.send(.payTapped) { $0.isLoading = true }
        await store.receive(\.payQuoteRefreshed) {
            $0.quote = refreshed
            $0.isLoading = false
            $0.isPayConfirmationPresented = true
        }
        await store.send(.payDismissed) { $0.isPayConfirmationPresented = false }
    }

    @MainActor
    @Test func scanningDoesNotCancelPaymentWaitingForDetails() async {
        var state = Offramp.State.initial(page: .amount, corridorContext: .payment)
        state.quote = quote()
        let waiting = progress(kind: "waiting_for_payment_details", title: "Merchant accepted")
        let pair = AsyncStream<OfframpProgressModel>.makeStream()
        let cancellation = CancellationFlag()
        pair.continuation.onTermination = { termination in
            if case .cancelled = termination { cancellation.markCancelled() }
        }
        let scan = OfframpScanResult(rawPayload: "upi://pay?pa=merchant", paymentAddress: "merchant", fiatAmount: nil)
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.pay = { _, _ in pair.stream }
            $0.offramp.parseQR = { _, _ in scan }
            $0.offramp.submitPaymentDetails = { _ in
                #expect(!cancellation.isCancelled)
                pair.continuation.finish()
            }
            $0.offramp.checkpointCurrencyCode = { nil }
            $0.offramp.topUpCheckpointMicros = { nil }
        }

        await store.send(.payConfirmed) {
            $0.page = .progress
            $0.isLoading = true
        }
        pair.continuation.yield(waiting)
        await store.receive(\.progressReceived) {
            $0.progress = [waiting]
            $0.page = .scanner
            $0.isLoading = false
        }
        await store.send(.scanPayload(scan.rawPayload)) { $0.isLoading = true }
        await store.receive(\.scanParsed) {
            $0.scan = scan
            $0.page = .progress
        }
        await store.receive(\.progressFinished) { $0.isLoading = false }
        await store.receive(\.checkpointsLoaded)
        #expect(!cancellation.isCancelled)
    }

    @MainActor
    @Test func topUpRequiresPreviewBeforeStartingBridge() async {
        var state = Offramp.State.initial(page: .topUp, corridorContext: .payment)
        state.topUpAmount = "2.5"
        // `startTopUpTapped` only proceeds for an amount that has already been validated.
        state.topUpValidatedMicros = "2500000"
        let preview = OfframpBridgePreview(
            sourceAmount: "0.1",
            sourceAsset: "ZEC",
            destinationAmount: "2.5",
            destinationAsset: "USDC on Base",
            networkFee: "0.0001",
            estimatedSeconds: 60
        )
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.previewTopUp = { _ in preview }
        }

        await store.send(.startTopUpTapped) { $0.isLoading = true }
        await store.receive(\.topUpPreviewLoaded) {
            $0.bridgePreview = preview
            $0.isLoading = false
            $0.isTopUpConfirmationPresented = true
        }
        await store.send(.topUpDismissed) {
            $0.bridgePreview = nil
            $0.isTopUpConfirmationPresented = false
        }
    }

    @MainActor
    @Test func authenticationCancellationRestoresAmountPage() async {
        var state = Offramp.State.initial(page: .amount, corridorContext: .payment)
        state.quote = quote()
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.offramp.pay = { _, _ in throw OfframpClientError.authenticationCancelled }
        }

        await store.send(.payConfirmed) {
            $0.page = .progress
            $0.isLoading = true
        }
        await store.receive(\.operationCancelled) {
            $0.page = .amount
            $0.isLoading = false
            $0.errorMessage = OfframpClientError.authenticationCancelled.localizedDescription
        }
    }

    /// Closing Scan & Pay owns only its reducer effects. Peer's runner belongs to the wallet and
    /// must survive ordinary navigation so an approval/create already in flight keeps its owner.
    @MainActor
    @Test func closingScreenDoesNotInvalidateWalletSession() async {
        let screenResets = LockIsolated(0)
        let sessionInvalidations = LockIsolated(0)
        let store = TestStore(initialState: Offramp.State.initial()) { Offramp() } withDependencies: {
            $0.offramp.resetScreen = { screenResets.withValue { $0 += 1 } }
            $0.offramp.invalidateSession = { sessionInvalidations.withValue { $0 += 1 } }
        }

        await store.send(.delegate(.close))
        await store.receive(\.cancelAll)
        await store.finish()

        #expect(screenResets.value == 1)
        #expect(sessionInvalidations.value == 0)
    }

    /// Root sends the Activity refund intent as soon as it mounts Offramp. The new screen's
    /// `onAppear` load must not cancel that already-running preview.
    @MainActor
    @Test func onAppearDoesNotCancelActivityRefundPreview() async {
        let previewStarted = AsyncStream<Void>.makeStream()
        var startedIterator = previewStarted.stream.makeAsyncIterator()
        let releasePreview = AsyncStream<Void>.makeStream()
        let cancellation = CancellationFlag()
        let preview = OfframpBridgePreview(
            sourceAmount: "2",
            sourceAsset: "USDC on Base",
            destinationAmount: "0.01",
            destinationAsset: "ZEC",
            networkFee: nil,
            estimatedSeconds: 60
        )
        let store = TestStore(initialState: Offramp.State.initial()) { Offramp() } withDependencies: {
            $0.peerCashOut.spendableBalance = {
                .ready(balance: UsdcAmount(micros: "2000000") ?? .zero, committed: .zero)
            }
            $0.offramp.previewRefund = {
                previewStarted.continuation.yield()
                previewStarted.continuation.finish()
                return try await withTaskCancellationHandler {
                    var iterator = releasePreview.stream.makeAsyncIterator()
                    guard await iterator.next() != nil else { throw CancellationError() }
                    return preview
                } onCancel: {
                    cancellation.markCancelled()
                }
            }
            $0.offramp.corridors = { [] }
            $0.offramp.checkpointCurrencyCode = { nil }
            $0.offramp.topUpCheckpointMicros = { nil }
            $0.offramp.accountSummary = { self.account() }
        }
        store.exhaustivity = .off

        await store.send(.refundTapped)
        _ = await startedIterator.next()
        await store.send(.onAppear)
        #expect(!cancellation.isCancelled)

        releasePreview.continuation.yield()
        releasePreview.continuation.finish()
        await store.receive(\.refundPreviewLoaded) {
            $0.bridgePreview = preview
            $0.isLoading = false
            $0.isRefundConfirmationPresented = true
        }
        #expect(!cancellation.isCancelled)
    }

    @MainActor
    @Test func unreadableReservationsFailRefundPreviewClosed() async {
        let store = TestStore(initialState: Offramp.State.initial()) { Offramp() } withDependencies: {
            $0.peerCashOut.spendableBalance = { .unavailable }
        }

        await store.send(.refundTapped) { $0.isLoading = true }
        await store.receive(\.loadFailed) {
            $0.isLoading = false
            $0.errorMessage = String(localizable: .peerFormErrorBalanceUnavailable)
        }
    }

    @Test func topUpAmountConvertsToUsdcMicrosWithoutRoundingUp() {
        #expect(Offramp.usdcMicros("2.5000009") == "2500000")
        #expect(Offramp.usdcMicros("0") == nil)
        #expect(Offramp.usdcMicros("") == nil)
    }

    @MainActor
    @Test func amountInputIsSanitizedAndInvalidatesQuote() async {
        var state = Offramp.State.initial(page: .amount)
        state.quote = quote()
        let store = TestStore(initialState: state) { Offramp() }

        // Letters go. Neither separator here has three digits behind it, so this is not a grouped
        // number and the first one is the point — a reading smaller than what was typed, which is
        // the direction a malformed amount has to fail in.
        await store.send(.fiatAmountChanged("1a2,3.4")) {
            $0.fiatAmount = "12.34"
            $0.quote = nil
        }

        // Grouping is three digits, and it is dropped rather than read as the decimal point:
        // `1,234.56` is the amount on screen, and taking the comma for the point would quote a
        // thousandth of it.
        await store.send(.fiatAmountChanged("1,234.56")) {
            $0.fiatAmount = "1234.56"
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

    private func quote(usdcMicros: String = "1000000") -> OfframpQuoteModel {
        OfframpQuoteModel(
            currencyCode: "INR",
            fiatAmount: "100",
            usdcMicros: usdcMicros,
            usdcDisplay: "1",
            sellRate: "100",
            fixedFeeDisplay: "0.1",
            requiredBalanceMicros: usdcMicros,
            baseBalanceDisplay: "2",
            shortfallMicros: "0",
            shortfallDisplay: "0",
            canPayFromBase: true,
            canBridgeToBase: true
        )
    }

    private func corridor(_ code: String) -> OfframpCorridor {
        OfframpCorridor(
            currencyCode: code,
            countryName: code == "INR" ? "India" : "Brazil",
            paymentRail: code == "INR" ? "UPI" : "PIX",
            flag: code == "INR" ? "🇮🇳" : "🇧🇷",
            symbol: code == "INR" ? "₹" : "R$",
            precision: 2
        )
    }

    private func account() -> OfframpAccountModel {
        OfframpAccountModel(
            address: "0xBase",
            balanceMicros: "0",
            balanceDisplay: "0",
            explorerURL: nil,
            canBridgeToBase: true,
            canRefundToZec: false
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

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool { lock.withLock { value } }

    func markCancelled() {
        lock.withLock { value = true }
    }
}
