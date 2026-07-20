//
//  ZappFiatRate.swift
//  Zapp
//
//  Mirrors Android's `zecFiatRate` (ui-lib/.../common/wallet/ZecFiatRate.kt).
//

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

enum ZappFiatRate {
    /// The opt-in CoinMarketCap conversion wins. When it is missing we fall back to the swap
    /// catalogue's ZEC price so a failed rate fetch doesn't strip fiat from the whole app.
    ///
    /// The fallback is USD-only, so it is used only when the user is opted in *and* has USD
    /// selected. Opting out shows no fiat at all, and a non-USD selection waits for the real
    /// conversion rather than showing a USD figure wearing another currency's symbol.
    static func resolve(
        conversion: CurrencyConversion?,
        swapAssets: IdentifiedArrayOf<SwapAsset>
    ) -> CurrencyConversion? {
        @Dependency(\.userStoredPreferences) var userStoredPreferences

        let preference = userStoredPreferences.exchangeRate()

        guard preference?.automatic == true else {
            return nil
        }

        if let conversion {
            return conversion
        }

        let selectedCurrency = preference?.currency ?? .usd

        guard selectedCurrency == .usd else {
            return nil
        }

        guard let price = zecUSDPrice(swapAssets), price > 0 else {
            return nil
        }

        return CurrencyConversion(.usd, ratio: price, timestamp: Date().timeIntervalSince1970)
    }

    private static func zecUSDPrice(_ swapAssets: IdentifiedArrayOf<SwapAsset>) -> Double? {
        var asset = swapAssets[id: SwapConstants.zecAssetIdOnNear]

        if asset == nil {
            asset = swapAssets.first { candidate in
                candidate.chain.lowercased() == "zec" && candidate.token.lowercased() == "zec"
            }
        }

        guard let asset else {
            return nil
        }

        return NSDecimalNumber(decimal: asset.usdPrice).doubleValue
    }
}
