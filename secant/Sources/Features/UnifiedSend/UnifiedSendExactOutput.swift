//
//  UnifiedSendExactOutput.swift
//  Zapp
//
//  The arithmetic behind the unified send's exact-output swap ("They receive exactly"), ported from
//  Android's `UnifiedSendEstimates.kt` and the amount half of `NearSwapDataSourceImpl.buildQuoteRequest`.
//
//  Only `baseUnits` is binding: it is the amount NEAR is asked to deliver. Everything else is a
//  client-side USD-price estimate that drives the non-authoritative half of the form and the pre-quote
//  balance check; the figures the user commits to come from the quote.
//
//  All amounts are `Decimal` end to end. Typed text is never parsed through `NumberFormatter`, which
//  goes through `Double` and can turn "0.3" into 0.29999… — one base unit short once truncated.
//

import Foundation

enum ExactOutputSwap {
    /// What was asked of NEAR for an exact-output quote, snapshotted when the request is built so the
    /// echo is checked against the request rather than against form state the user may have changed
    /// since (Android's `RequestSwapQuoteUseCase.requestExactOutput` snapshots the same way).
    struct Request: Equatable {
        let baseUnits: String
        let destinationDecimals: Int
        let originAssetId: String
        let destinationAssetId: String
        let destinationAddress: String
        let refundAddress: String
        let slippageBps: Int
    }

    /// Display precision: tokens show at most 8 fraction digits (the form's ZEC precision), USD 2.
    static let maxDisplayFractionDigits = 8
    static let usdFractionDigits = 2

    private static let posix = Locale(identifier: "en_US_POSIX")

    // MARK: - Parsing and formatting

    /// Parses an amount typed in `locale`. Accepts ASCII digits and at most one locale decimal
    /// separator, nothing else: stripping grouping separators would read "1.5" typed under a German
    /// locale as 15.
    static func decimal(from text: String, locale: Locale) -> Decimal? {
        let separator = locale.decimalSeparator ?? "."
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let normalized = trimmed.replacingOccurrences(of: separator, with: ".")
        guard
            !normalized.isEmpty,
            normalized != ".",
            normalized.allSatisfy({ ("0"..."9").contains($0) || $0 == "." }),
            normalized.filter({ $0 == "." }).count <= 1
        else {
            return nil
        }
        return Decimal(string: normalized, locale: posix)
    }

    /// Truncates (never rounds up) to `decimals` fraction digits. NEAR truncates the same way when it
    /// builds the request, so a finer amount could never reach the recipient.
    static func truncated(_ value: Decimal, decimals: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, max(decimals, 0), .down)
        return result
    }

    /// True when `value` carries more precision than the asset can settle (Android's
    /// `exceedsAssetDecimals`, which compares after stripping trailing zeros).
    static func exceedsDecimals(_ value: Decimal, decimals: Int) -> Bool {
        truncated(value, decimals: decimals) != value
    }

    /// Exact, locale-aware rendering with no grouping, truncated to `maxFractionDigits`.
    static func display(_ value: Decimal, maxFractionDigits: Int, locale: Locale) -> String {
        let plain = NSDecimalNumber(decimal: truncated(value, decimals: maxFractionDigits)).description(withLocale: posix)
        return plain.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    // MARK: - The binding amount

    /// The `amount` field of an EXACT_OUTPUT quote request: the destination amount in the asset's
    /// base units, rounded DOWN, as a plain integer string — what Android's `buildQuoteRequest` sends
    /// (`movePointRight(decimals)` then `RoundingMode.DOWN`). Nil for a non-positive amount.
    static func baseUnits(_ token: Decimal, decimals: Int) -> String? {
        guard token > 0, decimals >= 0 else { return nil }
        let shifted = truncated(token, decimals: decimals) * pow(Decimal(10), decimals)
        let integer = truncated(shifted, decimals: 0)
        guard integer > 0 else { return nil }
        let string = NSDecimalNumber(decimal: integer).description(withLocale: posix)
        guard string.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return string
    }

    // MARK: - Estimates (Android's `UnifiedSendEstimates.kt`)

    /// Estimated ZEC needed to deliver `token` of the destination asset.
    static func estimateZec(token: Decimal?, tokenUsdPrice: Decimal, zecUsdPrice: Decimal) -> Decimal? {
        divide(usd(token, price: tokenUsdPrice), by: zecUsdPrice)
    }

    /// Estimated destination amount `zec` buys — the "They receive ≈" figure.
    static func estimateToken(zec: Decimal?, zecUsdPrice: Decimal, tokenUsdPrice: Decimal) -> Decimal? {
        divide(usd(zec, price: zecUsdPrice), by: tokenUsdPrice)
    }

    /// USD value of `amount` at `price`. Nil when either is missing or the price is not positive.
    static func usd(_ amount: Decimal?, price: Decimal) -> Decimal? {
        guard let amount, price > 0 else { return nil }
        return amount * price
    }

    /// The amount `usd` buys at `price`.
    static func divide(_ usd: Decimal?, by price: Decimal) -> Decimal? {
        guard let usd, price > 0 else { return nil }
        return usd / price
    }

    // MARK: - Quote echo

    /// Fail-closed check of an exact-output quote before any proposal is built from it — Android's
    /// `requestExactOutput` validation plus the EXACT_OUTPUT half of `requireWithinSlippage`:
    /// - the destination amount is exactly what was requested,
    /// - origin/destination assets and both addresses are the ones requested,
    /// - the server's worst-case input (`minAmountIn`, a maximum for EXACT_OUTPUT) stays within the
    ///   requested slippage of `amountIn`, so a quote cannot quietly widen what we may be charged.
    static func quote(_ quote: SwapQuote, satisfies request: Request) -> Bool {
        guard let requested = Decimal(string: request.baseUnits, locale: posix) else { return false }
        let quotedUnits = quote.amountOut * pow(Decimal(10), request.destinationDecimals)
        var quotedRounded = quotedUnits
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotedRounded, 0, .plain)
        guard rounded == requested else { return false }
        guard
            quote.originAssetId == request.originAssetId,
            quote.destinationAssetId == request.destinationAssetId,
            quote.destinationAddress == request.destinationAddress,
            quote.refundAddress == request.refundAddress,
            quote.amountIn > 0
        else {
            return false
        }
        var ceiling = quote.amountIn * Decimal(10_000 + request.slippageBps) / Decimal(10_000)
        var ceilingRounded = Decimal()
        NSDecimalRound(&ceilingRounded, &ceiling, 0, .up)
        return quote.minAmountIn <= ceilingRounded
    }
}
