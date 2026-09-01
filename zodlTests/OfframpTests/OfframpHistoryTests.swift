// SPDX-License-Identifier: MIT OR Apache-2.0

import Testing
@testable import zodl_internal

struct OfframpHistoryTests {
    @Test(arguments: [
        ("BUY", OfframpHistoryOrderType.buy),
        ("SELL", OfframpHistoryOrderType.sell),
        ("PAY", OfframpHistoryOrderType.pay)
    ])
    func knownOrderTypesHaveLabels(value: String, expected: OfframpHistoryOrderType) throws {
        let item = history(orderType: value)
        let type = try #require(item.type)

        #expect(type == expected)
        #expect(!type.label.isEmpty)
    }

    @Test func unknownOrderTypeDoesNotCrash() {
        #expect(history(orderType: "FUTURE_TYPE").type == nil)
    }

    @Test func custodialBuyWithoutCounterpartyHandleRemainsRenderable() {
        let item = history(orderType: "BUY", paymentAddress: nil)

        #expect(item.type == .buy)
        #expect(item.paymentAddress == nil)
        #expect(!item.id.isEmpty)
    }

    private func history(orderType: String, paymentAddress: String? = "merchant@example") -> OfframpHistoryModel {
        OfframpHistoryModel(
            id: "659007",
            status: "CANCELLED",
            orderType: orderType,
            currencyCode: "INR",
            usdcMicros: "1190000",
            fiatMicros: "100000000",
            placedAt: nil,
            completedAt: nil,
            cancelledAt: nil,
            paymentAddress: paymentAddress,
            merchantAddress: "0xmerchant",
            fixedFeeMicros: "10000"
        )
    }
}
