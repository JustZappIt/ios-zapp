// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// A 6-decimal USDC amount, held in micro-units the way the chain reports them.
///
/// Amounts cross the Kotlin boundary as integer micro strings so nothing is rounded in transit.
/// Parsing one at every use site is how a comparison ends up made on a display string, so it is
/// parsed once, here, and an unparseable value is `nil` rather than zero — a balance that could not
/// be read and a balance of nothing are different answers, and only one of them permits a cash-out.
struct UsdcAmount: Equatable, Comparable, Sendable {
    static let zero = UsdcAmount(micros: 0)

    private static let microsPerUnit = Decimal(1_000_000)

    /// Always an integer: the initializers refuse anything that is not.
    let micros: Decimal

    private init(micros: Decimal) {
        self.micros = micros
    }

    /// The wire form: plain digits, which is all a chain read ever produces. Deliberately stricter
    /// than `Decimal(string:)`, which also accepts signs, separators and exponents — `1e6` parsing
    /// as a million is a reasonable thing for a formatter to do and a terrible thing for a balance.
    init?(micros: String) {
        guard !micros.isEmpty, micros.allSatisfy(\.isASCII), micros.allSatisfy(\.isNumber) else { return nil }
        guard let value = Decimal(string: micros) else { return nil }
        self.micros = value
    }

    /// Whole USDC as typed into an amount field. Truncates below a micro rather than rounding up,
    /// so the amount escrowed is never more than the user asked for.
    init?(whole: String) {
        guard let value = Decimal(string: whole), value >= 0 else { return nil }
        micros = (value * Self.microsPerUnit).rounded(.down)
    }

    /// How a USDC balance reads on screen: `0` for nothing, two decimals for ordinary amounts,
    /// and full precision only when there is something below the cent to show.
    ///
    /// The six-decimal wire form is right for arithmetic and wrong for a balance line — "0.000000"
    /// is noise. The shared Kotlin client asks for `toDisplayString(stripTrailingZeros = true)`,
    /// but `BigDecimal.stripTrailingZeros()` returns `0E-6` for zero, which renders straight back
    /// as "0.000000", so the trim has to happen here regardless.
    ///
    ///     0.000000 -> "0"        4.500000 -> "4.50"
    ///     4.000000 -> "4.00"     0.000123 -> "0.000123"
    static func displayBalance(_ display: String) -> String {
        guard let value = Decimal(string: display) else { return display }
        guard value != 0 else { return "0" }

        var trimmed = display
        if trimmed.contains(".") {
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
        }

        // Padding rather than reformatting: the wire value is exact and a round-trip through a
        // formatter is a chance to lose a digit off a balance.
        let fractionDigits = trimmed.split(separator: ".", maxSplits: 1).count > 1
            ? trimmed.split(separator: ".", maxSplits: 1)[1].count
            : 0
        switch fractionDigits {
        case 0: return "\(trimmed).00"
        case 1: return "\(trimmed)0"
        default: return trimmed
        }
    }

    var microsString: String { NSDecimalNumber(decimal: micros).stringValue }

    var whole: Decimal { micros / Self.microsPerUnit }

    var isPositive: Bool { micros > 0 }

    /// Never negative: the caller is asking what is left, and a shortfall is nothing left.
    func subtractingClampedToZero(_ other: UsdcAmount) -> UsdcAmount {
        UsdcAmount(micros: Swift.max(0, micros - other.micros))
    }

    static func + (lhs: UsdcAmount, rhs: UsdcAmount) -> UsdcAmount {
        UsdcAmount(micros: lhs.micros + rhs.micros)
    }

    static func < (lhs: UsdcAmount, rhs: UsdcAmount) -> Bool { lhs.micros < rhs.micros }

    static func sum(_ amounts: some Sequence<UsdcAmount>) -> UsdcAmount {
        amounts.reduce(.zero, +)
    }
}

extension UsdcAmount {
    /// Trailing zeros stripped: `20.000000` is noise beside a field the user typed `20` into.
    var display: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: whole)) ?? NSDecimalNumber(decimal: whole).stringValue
    }
}

private extension Decimal {
    func rounded(_ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, mode)
        return result
    }
}
