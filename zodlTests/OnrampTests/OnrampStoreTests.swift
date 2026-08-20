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

    @Test func aSecondPlacementTapCannotSendAnotherOrder() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .confirmation
        state.quote = quote()
        state.zecEstimate = estimate()
        let pair = AsyncStream<OnrampStatusModel>.makeStream()
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
                return AsyncStream { $0.finish() }
            }
        }

        await store.send(.paymentWindowExpired("order-1")) {
            $0.expiryRecheckedFor = "order-1"
        }
        await store.receive(.statusStreamFinished)
        await store.send(.paymentWindowExpired("order-1"))

        #expect(resumes.value == 1)
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
                return AsyncStream { $0.finish() }
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
                return AsyncStream { $0.finish() }
            }
        }
        let completed = OnrampStatusModel(
            kind: .completed,
            phase: .completed,
            id: "request-1",
            orderID: "659007",
            failureCode: nil,
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
