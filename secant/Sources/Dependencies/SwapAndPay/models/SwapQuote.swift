//
//  SwapQuote.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-06-18.
//

@preconcurrency import ZcashLightClientKit
import Foundation

struct SwapQuote: Codable, Equatable, Hashable {
    /// Deposit address (ZEC)
    let depositAddress: String
    /// Destination address echoed by the quote provider.
    let destinationAddress: String
    /// Refund address echoed by the quote provider.
    let refundAddress: String
    /// Origin asset identifier echoed by the quote provider.
    let originAssetId: String
    /// Destination asset identifier echoed by the quote provider.
    let destinationAssetId: String
    /// Amount of Zatoshi
    let amountIn: Decimal
    /// USD value of the Zatoshi amount, localized (0.1 vs. 0,1)
    let amountInUsd: String
    /// Minimal amount of Zatoshi so this quote can be procesed
    let minAmountIn: Decimal
    /// Amount that should be ideally received on the destination address
    let amountOut: Decimal
    /// USD value of the amount that will be received on the destination address, localized (0.1 vs. 0,1)
    let amountOutUsd: String
    /// Number of seconds it takes to process this quote
    let timeEstimate: TimeInterval
    /// Provider deadline echoed by the quote. Money-moving consumers reject stale routes.
    let deadline: Date
    
    init(
        depositAddress: String,
        destinationAddress: String,
        refundAddress: String,
        originAssetId: String,
        destinationAssetId: String,
        amountIn: Decimal,
        amountInUsd: String,
        minAmountIn: Decimal,
        amountOut: Decimal,
        amountOutUsd: String,
        timeEstimate: TimeInterval,
        deadline: Date = .distantFuture
    ) {
        self.depositAddress = depositAddress
        self.destinationAddress = destinationAddress
        self.refundAddress = refundAddress
        self.originAssetId = originAssetId
        self.destinationAssetId = destinationAssetId
        self.amountIn = amountIn
        self.amountInUsd = amountInUsd
        self.minAmountIn = minAmountIn
        self.amountOut = amountOut
        self.amountOutUsd = amountOutUsd
        self.timeEstimate = timeEstimate
        self.deadline = deadline
    }
}
