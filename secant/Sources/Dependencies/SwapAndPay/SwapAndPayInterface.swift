//
//  SwapAndPayInterface.swift
//  Zashi
//
//  Created by Lukáš Korba on 05-15-2025.
//

import ComposableArchitecture

extension DependencyValues {
    var swapAndPay: SwapAndPayClient {
        get { self[SwapAndPayClient.self] }
        set { self[SwapAndPayClient.self] = newValue }
    }
}

@DependencyClient
struct SwapAndPayClient {
    enum EndpointError: Equatable, Error {
        case message(String)
    }
    
    enum Constants {
        /// Affiliate fee in basis points. Zapp charges nothing on top of the 1Click quote;
        /// keep in sync with `AFFILIATE_FEE_BPS` in zapp-android.
        static let affiliateFeeBps = 0
        /// Recipient of the affiliate fee, used only when `affiliateFeeBps` is above zero.
        /// Keep in sync with `AFFILIATE_ADDRESS` in zapp-android.
        static let affiliateAddress = "042269ffc94d52b822b4bd053f9122c5a890a5483822421ac35a5236f63e390d"
    }
    
    var submitDepositTxId: @Sendable (String, String) async throws -> Void
    /// Curated offering — only the assets a user can select/swap.
    var swapAssets: @Sendable () async throws -> IdentifiedArrayOf<SwapAsset>
    /// Full provider catalog — for resolving/rendering historical or exotic assets
    /// that are no longer offered for swaps (MOB-1472).
    var swapAssetsCatalog: @Sendable () async throws -> IdentifiedArrayOf<SwapAsset>
    var quote: @Sendable (Bool, Bool, SwapQuoteMode, Int, SwapAsset, SwapAsset, String, String, String) async throws -> SwapQuote
    var status: @Sendable (String, Bool) async throws -> SwapDetails
}
