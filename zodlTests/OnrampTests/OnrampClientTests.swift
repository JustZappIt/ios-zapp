// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal
@preconcurrency import ZappOfframp

struct OnrampClientTests {
    /// How Kotlin/Native hands a thrown exception to Swift; the framework's `kotlinException` reads it back.
    private func kotlinError(_ exception: KotlinThrowable) -> NSError {
        NSError(domain: "KotlinException", code: 0, userInfo: ["KotlinException": exception])
    }

    @Test func aRefusedQuoteCrossesAsItsCodeNotTheDriversSentence() {
        let thrown = kotlinError(
            OnrampException(code: .capExceeded, httpStatus: 0, message: "amount is above both per-order limits")
        )
        let mapped = OnrampClientError.quoteRefusal(from: thrown)

        #expect(mapped as? OnrampClientError == .quoteRefused(.capExceeded))
        #expect(mapped.localizedDescription == String(localizable: .onrampErrorCapExceeded))
    }

    @Test func aDailyExhaustionCrossesAsItsOwnCode() {
        let thrown = kotlinError(
            OnrampException(code: .dailyLimitExceeded, httpStatus: 0, message: "no integrator orders left today")
        )

        #expect(OnrampClientError.quoteRefusal(from: thrown) as? OnrampClientError == .quoteRefused(.dailyLimitExceeded))
    }

    @Test func anythingElsePassesThroughUntouched() {
        struct Plain: Error, Equatable {}
        let plain = Plain()
        #expect(OnrampClientError.quoteRefusal(from: plain) as? Plain == plain)

        let other = kotlinError(KotlinIllegalStateException(message: "buy price is unreadable for this corridor"))
        #expect((OnrampClientError.quoteRefusal(from: other) as NSError) === other)
    }
}
