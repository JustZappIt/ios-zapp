// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// One implementation of "what the user meant by that amount", shared by every money field.
///
/// The separator is read from the number rather than from the locale, because this function
/// consumes its own output: the field is rebound to what it returns, so the next keystroke arrives
/// carrying the `.` this wrote. A filter that keeps only the locale's separator drops that `.`
/// again in every comma-decimal region, and `1,5` becomes `15` — ten times the amount, silently,
/// on its way to an escrow.
///
/// Grouping is what a separator followed by exactly three digits means, so `1,234.56` and
/// `1.234,56` both read as 1234.56. Anything else has one separator that counts, and it is the
/// decimal point: `1.234` reads as one and a bit rather than as a thousand, which is the direction
/// that under-reads rather than over-spends.
///
/// The result always uses `.`, because that is what `Decimal(string:)` parses.
enum DecimalAmountInput {
    /// - Parameter fractionDigits: the currency's precision. Six is USDC's, and also the finest a
    ///   micro amount can express, so a longer fraction is only a rounding surprise later.
    static func sanitized(_ value: String, fractionDigits: Int = 6) -> String {
        let allowed = value.filter { $0.isNumber || separators.contains($0) }
        guard let decimalIndex = decimalSeparatorIndex(in: allowed) else { return allowed }
        let whole = allowed[..<decimalIndex].filter(\.isNumber)
        let fraction = allowed[allowed.index(after: decimalIndex)...].filter(\.isNumber)
        return "\(whole).\(fraction.prefix(fractionDigits))"
    }

    /// The decimal point, or nil where the amount carries no separator at all. Every separator but
    /// the last has to look like grouping for the last one to be the point; otherwise this is a
    /// typed amount with a stray separator in it, and the first one is the one the user meant.
    private static func decimalSeparatorIndex(in value: String) -> String.Index? {
        let found = value.indices.filter { separators.contains(value[$0]) }
        guard let first = found.first, let last = found.last else { return nil }
        let isGrouped = zip(found, found.dropFirst()).allSatisfy { separator, next in
            value.distance(from: value.index(after: separator), to: next) == groupSize
        }
        return isGrouped ? last : first
    }

    private static let separators: Set<Character> = [".", ","]
    private static let groupSize = 3
}
