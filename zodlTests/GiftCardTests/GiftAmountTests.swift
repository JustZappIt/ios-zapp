// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ZcashLightClientKit
@testable import zodl_internal

@Suite struct GiftAmountTests {
    @Test func acceptsTheSmallestExactlyRepresentableAmount() throws {
        let amount = try #require(GiftAmount.fromZec(Decimal(string: "0.00000001")))

        #expect(amount.zatoshi == Zatoshi(1))
    }

    @Test func acceptsTheInclusiveZcashMonetaryMaximum() throws {
        let amount = try #require(GiftAmount.fromZec(Decimal(string: "21000000")))

        #expect(amount.zatoshi == Zatoshi(Zatoshi.Constants.maxZatoshi))
    }

    @Test func acceptsInsignificantDecimalZeroesWithoutRounding() throws {
        let amount = try #require(GiftAmount.fromZec(Decimal(string: "1.230000000")))

        #expect(amount.zatoshi == Zatoshi(123_000_000))
    }

    @Test func rejectsAbsentZeroAndNegativeAmounts() {
        #expect(GiftAmount.fromZec(nil) == nil)
        #expect(GiftAmount.fromZec(.zero) == nil)
        #expect(GiftAmount.fromZec(Decimal(string: "-1")) == nil)
    }

    @Test func rejectsAFractionalZatoshiInsteadOfTruncatingIt() {
        #expect(GiftAmount.fromZec(Decimal(string: "0.000000001")) == nil)
        #expect(GiftAmount.fromZec(Decimal(string: "1.000000001")) == nil)
    }

    @Test func rejectsValuesAboveTheMonetaryRangeWithoutClamping() {
        #expect(GiftAmount.fromZec(Decimal(string: "21000000.00000001")) == nil)
        #expect(GiftAmount.fromZec(Decimal(string: "1E+100")) == nil)
    }
}
