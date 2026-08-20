// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp
@preconcurrency import ZcashLightClientKit

final class OnrampZecSwapGateway: NSObject, AppleOnrampZecSwapGateway, @unchecked Sendable {
    private let worker: OnrampZecSwapWorker

    init(account: WalletAccount, swapAndPay: SwapAndPayClient, sdkSynchronizer: SDKSynchronizerClient) {
        worker = OnrampZecSwapWorker(
            account: account,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer
        )
    }

    func __quote(
        accountAddress: String,
        usdcMicros: String,
        completionHandler: @escaping @Sendable (AppleZecSwapQuote?, Error?) -> Void
    ) {
        Task { [worker] in
            do { completionHandler(try await worker.quote(accountAddress: accountAddress, usdcMicros: usdcMicros), nil) }
            catch { completionHandler(nil, error) }
        }
    }

    func __notifyDeposit(
        baseTransactionHash: String,
        depositAddress: String,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        Task { [worker] in
            do {
                try await worker.notifyDeposit(baseTransactionHash: baseTransactionHash, depositAddress: depositAddress)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    func __status(
        depositAddress: String,
        completionHandler: @escaping @Sendable (AppleZecSwapStatus?, Error?) -> Void
    ) {
        Task { [worker] in
            do { completionHandler(try await worker.status(depositAddress: depositAddress), nil) }
            catch { completionHandler(nil, error) }
        }
    }

    func invalidate() {
        Task { await worker.invalidate() }
    }
}

private actor OnrampZecSwapWorker {
    private enum Constants {
        static let exactInput = "EXACT_INPUT"
        static let slippageBasisPoints = 100
        static let slippagePercent = "1"
        static let microsPerUnit = Decimal(1_000_000)
        static let baseUsdcAssetID = "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near"
    }

    private let account: WalletAccount
    private let swapAndPay: SwapAndPayClient
    private let sdkSynchronizer: SDKSynchronizerClient
    private var isInvalidated = false

    init(account: WalletAccount, swapAndPay: SwapAndPayClient, sdkSynchronizer: SDKSynchronizerClient) {
        self.account = account
        self.swapAndPay = swapAndPay
        self.sdkSynchronizer = sdkSynchronizer
    }

    func quote(accountAddress: String, usdcMicros: String) async throws -> AppleZecSwapQuote {
        try requireActive()
        let assets = try await assets()
        let recipient = try await privateAddress()
        let quote = try await swapAndPay.quote(
            false,
            true,
            true,
            Constants.slippageBasisPoints,
            assets.zec,
            assets.usdc,
            recipient,
            accountAddress,
            usdcMicros
        )
        try requireActive()
        guard quote.originAssetId == assets.usdc.assetId,
              quote.destinationAssetId == assets.zec.assetId else {
            throw OnrampZecSwapError.routeMismatch
        }
        return AppleZecSwapQuote(
            mode: Constants.exactInput,
            inputUsdcMicros: try Self.micros(quote.amountIn),
            refundAddress: quote.refundAddress,
            recipientAddress: recipient,
            destinationAddress: quote.destinationAddress,
            depositAddress: quote.depositAddress,
            deadlineMillis: Int64(quote.deadline.timeIntervalSince1970 * 1_000),
            outputZec: Self.decimalString(quote.amountOut),
            inputUsd: try Self.usdString(quote.amountInUsd),
            outputUsd: try Self.usdString(quote.amountOutUsd),
            slippagePercent: Constants.slippagePercent
        )
    }

    func notifyDeposit(baseTransactionHash: String, depositAddress: String) async throws {
        try requireActive()
        try await swapAndPay.submitDepositTxId(baseTransactionHash, depositAddress)
    }

    func status(depositAddress: String) async throws -> AppleZecSwapStatus {
        try requireActive()
        let details = try await swapAndPay.status(depositAddress, true)
        try requireActive()
        guard let input = details.amountInFormatted,
              let refundAddress = details.refundAddress,
              let destinationAddress = details.swapRecipient,
              let echoedDeposit = details.depositAddress else {
            throw OnrampZecSwapError.missingStatusEcho
        }
        return AppleZecSwapStatus(
            status: details.status.onrampName,
            mode: details.swapType,
            inputUsdcMicros: try Self.micros(input),
            refundAddress: refundAddress,
            destinationAddress: destinationAddress,
            depositAddress: echoedDeposit,
            outputZec: details.amountOutFormatted.map(Self.decimalString) ?? "0",
            refundedUsdcMicros: try details.refundedAmountFormatted.map(Self.micros)
        )
    }

    func invalidate() {
        isInvalidated = true
    }

    private func requireActive() throws {
        guard !isInvalidated else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func privateAddress() async throws -> String {
        if let existing = account.privateUnifiedAddress { return existing }
        let address = try await sdkSynchronizer.getCustomUnifiedAddress(account.id, [.sapling, .orchard])
        guard let encoded = address?.stringEncoded else { throw OnrampZecSwapError.missingZcashAddress }
        return encoded
    }

    private func assets() async throws -> (zec: SwapAsset, usdc: SwapAsset) {
        let catalog = try await swapAndPay.swapAssetsCatalog()
        guard let zec = catalog.first(where: { $0.assetId == Near1Click.Constants.nearZecAssetId }) else {
            throw OnrampZecSwapError.missingAsset
        }
        guard let usdc = catalog.first(where: { $0.assetId == Constants.baseUsdcAssetID }) else {
            throw OnrampZecSwapError.missingAsset
        }
        return (zec, usdc)
    }

    private static func micros(_ value: Decimal) throws -> String {
        let number = NSDecimalNumber(decimal: value * Constants.microsPerUnit)
        let rounded = number.rounding(accordingToBehavior: DecimalIntegerRounding.shared)
        guard rounded.compare(number) == .orderedSame else { throw OnrampZecSwapError.fractionalMicros }
        return rounded.stringValue
    }

    private static func usdString(_ value: String) throws -> String {
        guard let decimal = value.localeUsdDecimal, decimal > 0 else { throw OnrampZecSwapError.invalidUsdValue }
        return decimalString(decimal)
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private final class DecimalIntegerRounding: NSObject, NSDecimalNumberBehaviors, @unchecked Sendable {
    static let shared = DecimalIntegerRounding()

    func roundingMode() -> Decimal.RoundingMode { .plain }
    func scale() -> Int16 { 0 }
    func exceptionDuringOperation(
        _ operation: Selector,
        error: Decimal.CalculationError,
        leftOperand: NSDecimalNumber,
        rightOperand: NSDecimalNumber?
    ) -> NSDecimalNumber? { nil }
}

private extension SwapDetails.Status {
    var onrampName: String {
        switch self {
        case .pending, .pendingDeposit: return "PENDING"
        case .processing: return "PROCESSING"
        case .success: return "SUCCESS"
        case .refunded: return "REFUNDED"
        case .failed: return "FAILED"
        case .expired: return "EXPIRED"
        case .incompleteDeposit: return "INCOMPLETE_DEPOSIT"
        }
    }
}

enum OnrampZecSwapError: Error {
    case fractionalMicros
    case invalidUsdValue
    case missingAsset
    case missingStatusEcho
    case missingZcashAddress
    case routeMismatch
}
