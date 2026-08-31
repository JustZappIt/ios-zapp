// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// One implementation of "what the user meant by that amount", shared by every money field.
///
/// Typing goes through a decimal pad, which emits the user's own separator and nothing else. A
/// paste does not: `1,234.56` carries a grouping separator as well, and a sanitizer that keeps the
/// first separator it sees reads that as `1.23456` — the amount that then gets escrowed is a
/// thousandth of the one on screen. The locale says which of the two is the decimal point, so the
/// other one is grouping and is dropped.
///
/// The result always uses `.`, because that is what `Decimal(string:)` parses.
enum DecimalAmountInput {
    /// - Parameter fractionDigits: the currency's precision. Six is USDC's, and also the finest a
    ///   micro amount can express, so a longer fraction is only a rounding surprise later.
    static func sanitized(_ value: String, fractionDigits: Int = 6) -> String {
        let separator: Character = Locale.current.decimalSeparator?.first ?? "."
        let allowed: String = value.filter { $0.isNumber || $0 == separator }
        let groups = allowed.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count > 1 else { return allowed }
        return "\(groups[0]).\(groups[1].prefix(fractionDigits))"
    }
}
