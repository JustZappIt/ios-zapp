//
//  PoolBalancesSheetTests.swift
//  zodlTests
//

import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite struct PoolBalancesSheetTests {
    @Test func visibleAccessibilityValueIncludesPreciseBalanceAndToken() {
        let balance = Zatoshi(123_456_789)

        let value = PoolBalancesSheet.accessibilityValue(
            balance: balance,
            tokenName: "ZEC",
            isSensitiveContentHidden: false
        )

        #expect(value == "\(balance.atLeastThreeDecimalsZashiFormatted()) ZEC")
    }

    @Test func hiddenAccessibilityValueMasksBothBalanceAndToken() {
        let value = PoolBalancesSheet.accessibilityValue(
            balance: Zatoshi(123_456_789),
            tokenName: "ZEC",
            isSensitiveContentHidden: true
        )

        #expect(value == String(localizable: .generalHideBalancesMost))
        #expect(!value.contains("ZEC"))
        #expect(!value.contains("1.23456789"))
    }
}
