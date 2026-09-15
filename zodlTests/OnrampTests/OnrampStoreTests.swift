// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized) @MainActor
struct OnrampStoreTests {
    @Test func backFromConfirmationReturnsToAmountAndClearsQuote() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .confirmation
        state.quote = quote()
        state.zecEstimate = estimate()
        state.quoteSecondsRemaining = 20
        let store = TestStore(initialState: state) { Onramp() }

        await store.send(.backTapped) {
            $0.page = .amount
            $0.quote = nil
            $0.zecEstimate = nil
            $0.quoteSecondsRemaining = nil
        }
    }

    /// Back on a finished order takes the start-over path: the checkpoint goes and the gate is checked again.
    @Test(arguments: [Onramp.Page.completion, .refundedToBase])
    func backFromAFinishedOrderStartsOverRatherThanLeaving(page: Onramp.Page) async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = page
        state.progress = completed()
        let clears = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.clearCheckpoint = { clears.withValue { $0 += 1 } }
        }
        store.exhaustivity = .off

        await store.send(.backTapped)
        await store.receive(.retryTapped)
        await store.receive(.delegate(.restartBuy))
        #expect(clears.value == 1)
        #expect(store.state.page == .loading)
    }

    @Test func backFromACancelledOrderStartsOver() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .progress
        state.progress = OnrampStatusModel(
            kind: .cancelled, phase: .cancelled, id: "743", orderID: "743", failureCode: nil, failureDetail: nil,
            instruction: nil, fiatMicros: nil, netUsdcMicros: nil, recipientAddress: nil, paidTransactionHash: nil,
            expiresAt: nil, isTerminal: true
        )
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.clearCheckpoint = { }
        }
        store.exhaustivity = .off

        await store.send(.backTapped)
        await store.receive(.retryTapped)
        await store.receive(.delegate(.restartBuy))
    }

    @Test func backFromALiveOrderLeavesWithTheCheckpointIntact() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .progress
        state.progress = OnrampStatusModel(
            kind: .awaitingMerchant, phase: .awaitingMerchant, id: "743", orderID: "743", failureCode: nil,
            failureDetail: nil, instruction: nil, fiatMicros: nil, netUsdcMicros: nil, recipientAddress: nil,
            paidTransactionHash: nil, expiresAt: nil, isTerminal: false
        )
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.clearCheckpoint = { Issue.record("a live order must keep its checkpoint") }
        }

        await store.send(.backTapped)
        await store.receive(.delegate(.close))
        #expect(!store.state.isSettled)
    }

    /// The dock offers Start over there, but that is a labelled button; Back is a reflex, and the
    /// order behind it is still accepted on chain with the merchant's USDC escrowed.
    @Test func backFromAPaymentTheAppRefusesToLetTheUserMakeKeepsTheOrder() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .payment
        state.paymentSecondsRemaining = 0
        state.progress = OnrampStatusModel(
            kind: .awaitingPayment, phase: .awaitingPayment, id: "743", orderID: "743", failureCode: nil,
            failureDetail: nil, instruction: .plain(address: "merchant"), fiatMicros: "100000000", netUsdcMicros: nil,
            recipientAddress: nil, paidTransactionHash: nil, expiresAt: nil, isTerminal: false
        )
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.clearCheckpoint = { Issue.record("a closed payment window must not discard the checkpoint") }
        }

        #expect(!store.state.isPayable)
        #expect(!store.state.isSettled)
        await store.send(.backTapped)
        await store.receive(.delegate(.close))
    }

    @Test func aSecondPlacementTapCannotSendAnotherOrder() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .confirmation
        state.quote = quote()
        state.zecEstimate = estimate()
        let pair = OnrampStatusStream.makeStream()
        let starts = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.start = { _, _, _ in
                starts.withValue { $0 += 1 }
                return pair.stream
            }
        }

        await store.send(.continueTapped) {
            $0.isPlacingOrder = true
            $0.page = .progress
        }
        await store.send(.continueTapped)
        #expect(starts.value == 1)

        pair.continuation.finish()
        await store.receive(.statusStreamFinished) {
            $0.isPlacingOrder = false
        }
    }

    @Test func paymentExpiryResumesOnlyOncePerOrder() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .payment
        let resumes = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.resume = {
                resumes.withValue { $0 += 1 }
                return OnrampStatusStream { $0.finish() }
            }
        }

        await store.send(.paymentWindowExpired("order-1")) {
            $0.expiryRecheckedFor = "order-1"
        }
        await store.receive(.recheckOrderTapped) {
            $0.isRecheckingOrder = true
        }
        await store.receive(.statusStreamFinished) {
            $0.isRecheckingOrder = false
        }
        await store.send(.paymentWindowExpired("order-1"))

        #expect(resumes.value == 1)
    }

    @Test func aRefusedQuoteStaysOnTheAmountPageWithTheCodesOwnSentence() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .amount
        state.amount = "1500"
        state.limits = OnrampLimitsModel(
            enabled: true,
            currencyCode: "INR",
            minimumFiatMicros: "106860000",
            maximumFiatMicros: "2035400000",
            dailyFiatMicros: "0"
        )
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.quote = { _, _ in throw OnrampClientError.quoteRefused(.dailyLimitExceeded) }
        }

        await store.send(.continueTapped) {
            $0.isRequestingQuote = true
        }
        await store.receive(.quoteFailed(String(localizable: .onrampErrorDailyLimit))) {
            $0.isRequestingQuote = false
            $0.errorMessage = String(localizable: .onrampErrorDailyLimit)
        }
        #expect(store.state.page == .amount)
        #expect(store.state.quote == nil)
    }

    @Test func aRefusalTheServiceExplainedShowsItsOwnSentence() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .progress
        let store = TestStore(initialState: state) { Onramp() }
        let refused = OnrampStatusModel(
            kind: .failed,
            phase: .placing,
            id: nil,
            orderID: nil,
            failureCode: .screeningRejected,
            failureDetail: "new accounts cannot place buy orders at this time",
            instruction: nil,
            fiatMicros: nil,
            netUsdcMicros: nil,
            recipientAddress: nil,
            paidTransactionHash: nil,
            expiresAt: nil,
            isTerminal: true
        )

        await store.send(.statusReceived(refused)) {
            $0.progress = refused
            $0.errorMessage = "new accounts cannot place buy orders at this time"
        }
    }

    @Test func aPendingSettlementResumesTheOrderRatherThanStartingOver() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .progress
        state.errorMessage = String(localizable: .onrampErrorSettlementPending)
        state.progress = OnrampStatusModel(
            kind: .failed,
            phase: .awaitingSettlement,
            id: "731906",
            orderID: "731906",
            failureCode: .settlementPending,
            failureDetail: nil,
            instruction: nil,
            fiatMicros: "100000000",
            netUsdcMicros: "1190000",
            recipientAddress: "0x1234",
            paidTransactionHash: "0xpaid",
            expiresAt: nil,
            isTerminal: true
        )
        let resumes = LockIsolated(0)
        let clears = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.resume = {
                resumes.withValue { $0 += 1 }
                return OnrampStatusStream { $0.finish() }
            }
            $0.onramp.clearCheckpoint = { clears.withValue { $0 += 1 } }
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
        }
        await store.receive(.statusStreamFinished)

        #expect(resumes.value == 1)
        #expect(clears.value == 0)
    }

    @Test func transientFailureResumesWithoutClearingCheckpoint() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .progress
        state.errorMessage = "offline"
        state.progress = OnrampStatusModel(
            kind: .failed,
            phase: .awaitingSettlement,
            id: "request-1",
            orderID: "order-1",
            failureCode: .networkUnavailable,
            failureDetail: nil,
            instruction: nil,
            fiatMicros: "100000000",
            netUsdcMicros: "1190000",
            recipientAddress: "0x1234",
            paidTransactionHash: nil,
            expiresAt: nil,
            isTerminal: false
        )
        let resumes = LockIsolated(0)
        let clears = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.resume = {
                resumes.withValue { $0 += 1 }
                return OnrampStatusStream { $0.finish() }
            }
            $0.onramp.clearCheckpoint = { clears.withValue { $0 += 1 } }
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
        }
        await store.receive(.statusStreamFinished)

        #expect(resumes.value == 1)
        #expect(clears.value == 0)
    }

    @Test func zecDeliveryUsesCheckpointRequestIDNotServiceOrderID() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .progress
        let deliveredIDs = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.deliverToZec = { id, _, _ in
                deliveredIDs.withValue { $0.append(id) }
                return OnrampDeliveryStream { $0.finish() }
            }
        }
        let completed = OnrampStatusModel(
            kind: .completed,
            phase: .completed,
            id: "request-1",
            orderID: "659007",
            failureCode: nil,
            failureDetail: nil,
            instruction: nil,
            fiatMicros: "100000000",
            netUsdcMicros: "1190000",
            recipientAddress: "0x1234",
            paidTransactionHash: nil,
            expiresAt: nil,
            isTerminal: true
        )

        await store.send(.statusReceived(completed)) {
            $0.progress = completed
            $0.requestID = "request-1"
            $0.orderID = "659007"
            $0.receivedUsdc = "1.19"
            $0.fiatPaid = "100"
            $0.page = .convertingToZec
            $0.deliveryStartedFor = "request-1"
        }
        await store.receive(.deliveryStreamFinished)

        #expect(deliveredIDs.value == ["request-1"])
    }

    @Test func relaunchAfterARefundReplaysItInsteadOfSpendingItAgain() async {
        let state = Onramp.State.initial(currencyCode: "INR")
        let resumes = LockIsolated(0)
        let retries = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.resumeDelivery = {
                resumes.withValue { $0 += 1 }
                return OnrampDeliveryStream { $0.finish() }
            }
            $0.onramp.retryDelivery = {
                retries.withValue { $0 += 1 }
                return OnrampDeliveryStream { $0.finish() }
            }
        }
        let checkpoint = OnrampCheckpointModel(
            id: "request-1",
            phase: .completed,
            orderID: "order-1",
            destination: .zcash,
            zecDelivery: OnrampDeliveryCheckpointModel(
                phase: .refundedToBase,
                usdcMicros: "1190000",
                baseAccount: "0x1234",
                transferStarted: true,
                refundedUsdcMicros: "1180000",
                acceptedCostBasisPoints: 168,
                fundsLocation: .baseAccount
            )
        )

        await store.send(.resumeLoadedCheckpoint(checkpoint)) {
            $0.requestID = "request-1"
            $0.orderID = "order-1"
        }
        await store.receive(.deliveryStreamFinished)

        #expect(resumes.value == 1)
        #expect(retries.value == 0)
    }

    @Test func aLapsedPaymentWindowCannotDiscardTheCheckpoint() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .payment
        state.paymentSecondsRemaining = 0
        state.orderID = "order-1"
        state.progress = OnrampStatusModel(
            kind: .awaitingPayment,
            phase: .awaitingPayment,
            id: "request-1",
            orderID: "order-1",
            failureCode: nil,
            failureDetail: nil,
            instruction: .plain(address: "merchant"),
            fiatMicros: "100000000",
            netUsdcMicros: nil,
            recipientAddress: nil,
            paidTransactionHash: nil,
            expiresAt: nil,
            isTerminal: false
        )
        let clears = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.resume = { OnrampStatusStream { $0.finish() } }
            $0.onramp.clearCheckpoint = { clears.withValue { $0 += 1 } }
        }

        await store.send(.retryTapped)
        await store.receive(.recheckOrderTapped) {
            $0.isRecheckingOrder = true
        }
        await store.receive(.statusStreamFinished) {
            $0.isRecheckingOrder = false
        }

        #expect(clears.value == 0)
    }

    @Test func aRefundTheBridgeRejectsIsNotReportedAsSent() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .amount
        state.baseBalance = "12.50"
        state.baseRefundState = .available
        state.baseRefundPreview = preview()
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.offramp.recoverFunds = { _ in
                AsyncStream { continuation in
                    continuation.yield(Self.progress(kind: "failed", isTerminal: true, isSuccess: false))
                    continuation.finish()
                }
            }
        }

        await store.send(.sendBaseBalanceToZecConfirmed) {
            $0.isSendBaseBalanceConfirmationPresented = false
            $0.isSendingBaseBalanceToZec = true
            $0.baseRefundState = .inProgress
        }
        await store.receive(.baseBalanceSendFailed(String(localizable: .onrampSendToZecFailed))) {
            $0.isSendingBaseBalanceToZec = false
            $0.baseRefundPreview = nil
            $0.baseRefundState = .failedRetry
            $0.errorMessage = String(localizable: .onrampSendToZecFailed)
        }
        #expect(store.state.baseBalance == "12.50")
    }

    @Test func aRefundStreamThatEndsWithoutATerminalStatusIsNotSuccess() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.baseBalance = "12.50"
        state.baseRefundState = .available
        state.baseRefundPreview = preview()
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.offramp.recoverFunds = { _ in AsyncStream { $0.finish() } }
        }

        await store.send(.sendBaseBalanceToZecConfirmed) {
            $0.isSendBaseBalanceConfirmationPresented = false
            $0.isSendingBaseBalanceToZec = true
            $0.baseRefundState = .inProgress
        }
        await store.receive(.baseBalanceSendFailed(String(localizable: .onrampSendToZecFailed))) {
            $0.isSendingBaseBalanceToZec = false
            $0.baseRefundPreview = nil
            $0.baseRefundState = .failedRetry
            $0.errorMessage = String(localizable: .onrampSendToZecFailed)
        }
        #expect(store.state.baseBalance == "12.50")
    }

    @Test func aSuccessfulRefundClearsTheBaseBalance() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.baseBalance = "12.50"
        state.baseRefundState = .available
        state.baseRefundPreview = preview()
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.offramp.recoverFunds = { _ in
                AsyncStream { continuation in
                    continuation.yield(Self.progress(kind: "waiting", isTerminal: false, isSuccess: false))
                    continuation.yield(Self.progress(kind: "funds_recovered", isTerminal: true, isSuccess: true))
                    continuation.finish()
                }
            }
        }

        await store.send(.sendBaseBalanceToZecConfirmed) {
            $0.isSendBaseBalanceConfirmationPresented = false
            $0.isSendingBaseBalanceToZec = true
            $0.baseRefundState = .inProgress
        }
        await store.receive(.baseBalanceSent) {
            $0.isSendingBaseBalanceToZec = false
            $0.baseRefundPreview = nil
            $0.baseBalance = nil
            $0.baseRefundState = .hidden
        }
    }

    @Test func theRefundIsQuotedBeforeTheSheetAsksToSendIt() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.baseBalance = "12.50"
        state.baseRefundState = .available
        let previews = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.offramp.previewRefund = {
                previews.withValue { $0 += 1 }
                return Self.previewValue
            }
        }

        await store.send(.sendBaseBalanceToZecTapped) {
            $0.baseRefundState = .inProgress
        }
        await store.receive(.baseRefundPreviewLoaded(Self.previewValue)) {
            $0.baseRefundPreview = Self.previewValue
            $0.baseRefundState = .available
            $0.isSendBaseBalanceConfirmationPresented = true
        }
        #expect(previews.value == 1)
    }

    @Test func anUnquotedRefundCannotBeConfirmed() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.baseBalance = "12.50"
        state.baseRefundState = .available
        state.isSendBaseBalanceConfirmationPresented = true
        let recoveries = LockIsolated(0)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.offramp.recoverFunds = { _ in
                recoveries.withValue { $0 += 1 }
                return AsyncStream { $0.finish() }
            }
        }

        await store.send(.sendBaseBalanceToZecConfirmed)
        #expect(recoveries.value == 0)
    }

    private nonisolated static let previewValue = OfframpBridgePreview(
        sourceAmount: "12.50",
        sourceAsset: "USDC on Base",
        destinationAmount: "0.045",
        destinationAsset: "ZEC",
        networkFee: "0.0001",
        estimatedSeconds: 60
    )

    private func preview() -> OfframpBridgePreview { Self.previewValue }

    private nonisolated static func progress(kind: String, isTerminal: Bool, isSuccess: Bool) -> OfframpProgressModel {
        OfframpProgressModel(
            kind: kind,
            step: "WAITING_FOR_ACCEPTANCE",
            title: "Funds returned",
            detail: isSuccess ? nil : "The refund quote was never authorized",
            orderId: nil,
            txHash: nil,
            bridgeDepositAddress: nil,
            isTerminal: isTerminal,
            isSuccess: isSuccess
        )
    }

    private func completed() -> OnrampStatusModel {
        OnrampStatusModel(
            kind: .completed, phase: .completed, id: "743", orderID: "743", failureCode: nil, failureDetail: nil,
            instruction: nil, fiatMicros: "100000000", netUsdcMicros: "1190000", recipientAddress: "0x1234",
            paidTransactionHash: nil, expiresAt: nil, isTerminal: true
        )
    }

    private func quote() -> OnrampQuoteModel {
        OnrampQuoteModel(
            quoteID: "quote-1",
            currencyCode: "INR",
            fiatMicros: "100000000",
            grossUsdcMicros: "1200000",
            feeUsdcMicros: "10000",
            netUsdcMicros: "1190000",
            buyPriceMicros: "83333333",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    private func estimate() -> OnrampZecEstimateModel {
        OnrampZecEstimateModel(
            depositAddress: "near-deposit",
            zcashRecipient: "u1test",
            deadline: Date(timeIntervalSince1970: 2_000_000_000),
            outputZec: "0.025",
            inputUsd: "1.19",
            outputUsd: "1.17",
            costBasisPoints: 168
        )
    }
}
