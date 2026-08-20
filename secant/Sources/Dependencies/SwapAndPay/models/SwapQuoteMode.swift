// SPDX-License-Identifier: MIT OR Apache-2.0
//
//  SwapQuoteMode.swift
//  Zapp
//

/// How the provider should price a quote. Named rather than derived from booleans: the same
/// `isSwapToZec` route is deposited into by hand from an external wallet, where the amount that
/// arrives is whatever the user sends, and automatically from the Base account, where the caller
/// pins an exact input and validates the echo.
enum SwapQuoteMode: String, Equatable, Sendable {
    case exactInput = "EXACT_INPUT"
    case exactOutput = "EXACT_OUTPUT"
    case flexInput = "FLEX_INPUT"
}
