// SPDX-License-Identifier: MIT OR Apache-2.0

import Testing
import Foundation
@testable import zodl_internal

/// The amount sanitizer shared by every money field (Utils/DecimalAmountInput.swift).
///
/// The important cases are the typed ones. A money field is bound to the sanitized string, so each
/// keystroke re-enters what the previous one returned: sanitizing once proves nothing about what
/// the second keystroke does, which is where a dropped separator turns 1,5 into 15.
@Suite struct DecimalAmountInputTests {
    /// Feeds keys through the field's binding the way the reducer does: sanitize, rebind, repeat.
    private func typed(_ keys: String) -> String {
        keys.reduce("") { DecimalAmountInput.sanitized($0 + String($1)) }
    }

    @Test func aCommaTypedAmountKeepsItsFraction() {
        #expect(typed("1,5") == "1.5")
        #expect(typed("1,50") == "1.50")
        #expect(typed("0,25") == "0.25")
    }

    @Test func aDotTypedAmountKeepsItsFraction() {
        #expect(typed("1.5") == "1.5")
        #expect(typed("1.50") == "1.50")
        #expect(typed("0.25") == "0.25")
    }

    /// The separator cannot come from the locale: what this returns is what the next keystroke
    /// carries back in, so both characters have to survive a round trip whatever the region is.
    @Test func sanitizingIsIdempotent() {
        for value in ["1.5", "1.50", "0.25", "20", "20.", "1234.56"] {
            #expect(DecimalAmountInput.sanitized(value) == value)
        }
    }

    /// A second separator is a typo on an amount that already has its point, not grouping.
    @Test func aStraySecondSeparatorDoesNotShiftThePoint() {
        #expect(typed("1.5,0") == "1.50")
        #expect(DecimalAmountInput.sanitized("1.5.") == "1.5")
        #expect(DecimalAmountInput.sanitized("1,5,") == "1.5")
        // Two separators, neither of them grouping: the first is the point, so the amount reads
        // smaller than it was typed rather than larger.
        #expect(DecimalAmountInput.sanitized("12,3.4") == "12.34")
    }

    /// Pasting carries grouping, which typing never does. Three digits after a separator is what
    /// makes it grouping, so both conventions read the same.
    @Test func groupedPasteDropsItsGroupingSeparators() {
        #expect(DecimalAmountInput.sanitized("1,234.56") == "1234.56")
        #expect(DecimalAmountInput.sanitized("1.234,56") == "1234.56")
        #expect(DecimalAmountInput.sanitized("12,345,678.90") == "12345678.90")
        #expect(DecimalAmountInput.sanitized("1 234.56") == "1234.56")
    }

    /// Ambiguous on its own, and read as the point: under-reading an amount is recoverable, and
    /// escrowing a thousand times the one on screen is not.
    @Test func aLoneSeparatorIsAlwaysTheDecimalPoint() {
        #expect(DecimalAmountInput.sanitized("1.234") == "1.234")
        #expect(DecimalAmountInput.sanitized("1,234") == "1.234")
    }

    @Test func theFractionIsTruncatedToTheGivenPrecision() {
        #expect(DecimalAmountInput.sanitized("1.1234567") == "1.123456")
        #expect(DecimalAmountInput.sanitized("1.1234567", fractionDigits: 2) == "1.12")
        #expect(DecimalAmountInput.sanitized("1,1234567") == "1.123456")
    }

    @Test func everythingThatIsNotAnAmountIsDropped() {
        #expect(DecimalAmountInput.sanitized("").isEmpty)
        #expect(DecimalAmountInput.sanitized("abc").isEmpty)
        #expect(DecimalAmountInput.sanitized("20 USDC") == "20")
        #expect(DecimalAmountInput.sanitized("-20") == "20")
    }

    /// The output is what `Decimal(string:)` parses, which is the only reason the point is `.`.
    @Test func theResultParsesAsTheAmountThatWasTyped() throws {
        #expect(try #require(Decimal(string: typed("1,5"))) == Decimal(string: "1.5"))
        #expect(try #require(Decimal(string: typed("0,25"))) == Decimal(string: "0.25"))
        #expect(try #require(Decimal(string: DecimalAmountInput.sanitized("1.234,56"))) == Decimal(string: "1234.56"))
    }
}
