// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ZcashLightClientKit

/// A positive, exactly representable gift-card amount within the Zcash monetary range.
///
/// Keeping the conversion behind this type prevents a decimal UI value from reaching funding after
/// it has been rounded to eight decimal places, or silently clamped: `Zatoshi.from(decimal:)`
/// banker's-rounds and the `Zatoshi` initializer clamps, and both silently alter the value.
struct GiftAmount: Equatable {
    let zatoshi: Zatoshi

    private init(zatoshi: Zatoshi) {
        self.zatoshi = zatoshi
    }

    /// Multiplication by 10^8 is an exact exponent shift on `Decimal`; the round-trip compare then
    /// rejects fractional zatoshi rather than rounding them, and the bound is checked on the raw
    /// integer before any `Zatoshi` is constructed.
    static func fromZec(_ amount: Decimal?) -> GiftAmount? {
        guard let amount, amount > 0 else { return nil }
        let zats = amount * Decimal(Zatoshi.Constants.oneZecInZatoshi)
        guard zats <= Decimal(Zatoshi.Constants.maxZatoshi) else { return nil }
        var value = zats
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        guard rounded == zats else { return nil }
        let raw = NSDecimalNumber(decimal: zats).int64Value
        guard Decimal(raw) == zats else { return nil }
        return GiftAmount(zatoshi: Zatoshi(raw))
    }
}
