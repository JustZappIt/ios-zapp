// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

struct OnrampProgressMapperTests {
    @Test func refundedDeliveryFailsOnConversionRow() throws {
        let delivery = OnrampDeliveryModel(
            kind: .refundedToBase,
            stage: .refundedToBase,
            inputUsdcMicros: "1250000",
            outputZec: nil,
            refundedUsdcMicros: "1240000",
            baseAccount: "0x1234",
            baseTransactionHash: "0xfeed",
            fundsLocation: .baseRefundConfirmed,
            retryable: false,
            isTerminal: true,
            isSuccess: false
        )

        let steps = OnrampProgressMapper.map(status: nil, delivery: delivery, destination: .zcash)
        let conversion = try #require(steps.first { $0.step == .convertingToZec })
        let received = try #require(steps.first { $0.step == .zecReceived })

        #expect(conversion.status == .failed)
        #expect(received.status == .pending)
    }

    @Test func paymentWindowExpiryFailsPayRow() throws {
        let steps = OnrampProgressMapper.map(status: status(phase: .expired, failure: .orderExpired))
        let pay = try #require(steps.first { $0.step == .payMerchant })
        let merchant = try #require(steps.first { $0.step == .merchantMatched })

        #expect(pay.status == .failed)
        #expect(merchant.status == .completed)
    }

    @Test func nonPaymentExpiryFailsMerchantRow() throws {
        let steps = OnrampProgressMapper.map(status: status(phase: .expired, failure: .noMerchant))
        let merchant = try #require(steps.first { $0.step == .merchantMatched })
        let pay = try #require(steps.first { $0.step == .payMerchant })

        #expect(merchant.status == .failed)
        #expect(pay.status == .pending)
    }

    private func status(
        phase: OnrampPhaseModel,
        failure: OnrampFailureCodeModel
    ) -> OnrampStatusModel {
        OnrampStatusModel(
            kind: .failed,
            phase: phase,
            id: "request-1",
            orderID: "order-1",
            failureCode: failure,
            instruction: nil,
            fiatMicros: "100000000",
            netUsdcMicros: "1000000",
            recipientAddress: "0x1234",
            paidTransactionHash: nil,
            expiresAt: nil,
            isTerminal: true
        )
    }
}
