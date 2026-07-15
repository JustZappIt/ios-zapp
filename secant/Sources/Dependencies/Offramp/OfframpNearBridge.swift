// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp
@preconcurrency import ZcashLightClientKit

/// iOS wallet/1-Click half of the shared bridge contract. Preparing is read-only; execute sends the
/// already-persisted quote exactly once; resume only polls the existing deposit address.
final class OfframpNearBridge: NSObject, AppleOfframpBridge, @unchecked Sendable {
    private let worker: OfframpNearBridgeWorker

    init(
        account: WalletAccount,
        swapAndPay: SwapAndPayClient,
        sdkSynchronizer: SDKSynchronizerClient,
        walletStorage: WalletStorageClient,
        mnemonic: MnemonicClient,
        derivationTool: DerivationToolClient,
        environment: ZcashSDKEnvironment
    ) {
        worker = OfframpNearBridgeWorker(
            account: account,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer,
            walletStorage: walletStorage,
            mnemonic: mnemonic,
            derivationTool: derivationTool,
            environment: environment
        )
    }

    func __prepare(
        accountAddress: String,
        usdcMicros: String,
        completionHandler: @escaping @Sendable (String?, Error?) -> Void
    ) {
        Task {
            do { completionHandler(try await worker.prepare(accountAddress: accountAddress, usdcMicros: usdcMicros), nil) }
            catch { completionHandler(nil, error) }
        }
    }

    func __execute(
        depositAddress: String,
        completionHandler: @escaping @Sendable (AppleBridgeExecution?, Error?) -> Void
    ) {
        Task {
            do { completionHandler(try await worker.execute(depositAddress: depositAddress), nil) }
            catch { completionHandler(nil, error) }
        }
    }

    func __resume(
        depositAddress: String,
        completionHandler: @escaping @Sendable (AppleBridgeExecution?, Error?) -> Void
    ) {
        Task { completionHandler(await worker.poll(depositAddress: depositAddress), nil) }
    }

    func __prepareRefund(
        accountAddress: String,
        usdcMicros: String,
        completionHandler: @escaping @Sendable (String?, Error?) -> Void
    ) {
        Task {
            do {
                completionHandler(
                    try await worker.prepareRefund(accountAddress: accountAddress, usdcMicros: usdcMicros),
                    nil
                )
            } catch { completionHandler(nil, error) }
        }
    }

}

private actor OfframpNearBridgeWorker {
    private struct PreparedBridge {
        let quote: SwapQuote
    }

    private let account: WalletAccount
    private let swapAndPay: SwapAndPayClient
    private let sdkSynchronizer: SDKSynchronizerClient
    private let walletStorage: WalletStorageClient
    private let mnemonic: MnemonicClient
    private let derivationTool: DerivationToolClient
    private let environment: ZcashSDKEnvironment
    private var prepared: [String: PreparedBridge] = [:]

    init(
        account: WalletAccount,
        swapAndPay: SwapAndPayClient,
        sdkSynchronizer: SDKSynchronizerClient,
        walletStorage: WalletStorageClient,
        mnemonic: MnemonicClient,
        derivationTool: DerivationToolClient,
        environment: ZcashSDKEnvironment
    ) {
        self.account = account
        self.swapAndPay = swapAndPay
        self.sdkSynchronizer = sdkSynchronizer
        self.walletStorage = walletStorage
        self.mnemonic = mnemonic
        self.derivationTool = derivationTool
        self.environment = environment
    }

    func prepare(accountAddress: String, usdcMicros: String) async throws -> String {
        let assets = try await assets()
        let refundAddress = try await privateAddress()
        let quote = try await swapAndPay.quote(
            false,
            false,
            false,
            100,
            assets.zec,
            assets.usdc,
            refundAddress,
            accountAddress,
            usdcMicros
        )
        try OfframpBridgeQuoteValidator.validate(
            quote,
            requestedMicros: usdcMicros,
            destinationAddress: accountAddress,
            refundAddress: refundAddress,
            originAssetId: assets.zec.assetId,
            destinationAssetId: assets.usdc.assetId
        )
        prepared[quote.depositAddress] = PreparedBridge(quote: quote)
        return quote.depositAddress
    }

    func execute(depositAddress: String) async throws -> AppleBridgeExecution {
        guard let bridge = prepared.removeValue(forKey: depositAddress) else {
            return AppleBridgeExecution(
                succeeded: false,
                terminal: false,
                message: "The prepared bridge quote is no longer available. Resume the existing transfer."
            )
        }
        guard account.vendor == .zcash, let accountIndex = account.zip32AccountIndex else {
            return AppleBridgeExecution(
                succeeded: false,
                terminal: true,
                message: "Adding funds from a Keystone account is not supported yet."
            )
        }

        let recipient = try Recipient(bridge.quote.depositAddress, network: environment.network().networkType)
        let amount = Zatoshi(NSDecimalNumber(decimal: bridge.quote.amountIn).int64Value)
        let proposal = try await sdkSynchronizer.proposeTransfer(account.id, recipient, amount, nil)
        let storedWallet = try walletStorage.exportWallet()
        let seedBytes = try mnemonic.toSeed(storedWallet.seedPhrase.value())
        let spendingKey = try derivationTool.deriveSpendingKey(
            seedBytes,
            accountIndex,
            environment.network().networkType
        )
        let result = try await sdkSynchronizer.createAndSubmitProposedTransactions(proposal, spendingKey)
        let txId: String
        switch result {
        case .success(let txIds):
            guard let value = txIds.last else { throw OfframpBridgeError.missingTransactionId }
            txId = value
        case .grpcFailure(let txIds, _):
            guard let value = txIds.last else { throw OfframpBridgeError.missingTransactionId }
            txId = value
        case .failure(_, let code, let description):
            throw OfframpBridgeError.submissionFailed("\(code): \(description)")
        case .partial(_, let statuses):
            throw OfframpBridgeError.submissionFailed(statuses.joined(separator: ", "))
        }
        try? await swapAndPay.submitDepositTxId(txId, depositAddress)
        return await poll(depositAddress: depositAddress)
    }

    func prepareRefund(accountAddress: String, usdcMicros: String) async throws -> String {
        let assets = try await assets()
        let zecAddress = try await privateAddress()
        let quote = try await swapAndPay.quote(
            false,
            true,
            true,
            100,
            assets.zec,
            assets.usdc,
            zecAddress,
            accountAddress,
            usdcMicros
        )
        try OfframpBridgeQuoteValidator.validateRefund(
            quote,
            requestedMicros: usdcMicros,
            destinationAddress: zecAddress,
            refundAddress: accountAddress,
            originAssetId: assets.usdc.assetId,
            destinationAssetId: assets.zec.assetId
        )
        return quote.depositAddress
    }

    func poll(depositAddress: String) async -> AppleBridgeExecution {
        var deterministicFailures = 0
        while !Task.isCancelled {
            do {
                let details = try await swapAndPay.status(depositAddress, false)
                deterministicFailures = 0
                switch details.status {
                case .success:
                    return AppleBridgeExecution(succeeded: true, terminal: false, message: nil)
                case .failed, .refunded, .expired, .incompleteDeposit:
                    return AppleBridgeExecution(
                        succeeded: false,
                        terminal: true,
                        message: "The 1-Click bridge ended with status \(details.status.rawName)."
                    )
                case .pending, .pendingDeposit, .processing:
                    break
                }
            } catch {
                deterministicFailures += 1
                if deterministicFailures >= 3 {
                    return AppleBridgeExecution(succeeded: false, terminal: false, message: error.localizedDescription)
                }
            }
            try? await Task.sleep(for: .seconds(5))
        }
        return AppleBridgeExecution(succeeded: false, terminal: false, message: "Bridge polling was cancelled.")
    }

    private func privateAddress() async throws -> String {
        if let existing = account.privateUnifiedAddress { return existing }
        let address = try await sdkSynchronizer.getCustomUnifiedAddress(account.id, [.sapling, .orchard])
        guard let encoded = address?.stringEncoded else { throw OfframpBridgeError.missingRefundAddress }
        return encoded
    }

    private func assets() async throws -> (zec: SwapAsset, usdc: SwapAsset) {
        let catalog = try await swapAndPay.swapAssetsCatalog()
        guard let zec = catalog.first(where: { $0.assetId == Near1Click.Constants.nearZecAssetId }) else {
            throw OfframpBridgeError.missingAsset("ZEC")
        }
        guard let usdc = catalog.first(where: {
            $0.assetId == "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near"
        }) else {
            throw OfframpBridgeError.missingAsset("USDC on Base")
        }
        return (zec, usdc)
    }

}

enum OfframpBridgeQuoteValidator {
    static func validate(
        _ quote: SwapQuote,
        requestedMicros: String,
        destinationAddress: String,
        refundAddress: String,
        originAssetId: String,
        destinationAssetId: String
    ) throws {
        let deliveredMicros = NSDecimalNumber(decimal: quote.amountOut * 1_000_000).stringValue
        guard deliveredMicros == requestedMicros else {
            throw OfframpBridgeError.quoteMismatch(
                field: "amountOut",
                expected: requestedMicros,
                actual: deliveredMicros
            )
        }
        guard quote.destinationAddress == destinationAddress else {
            throw OfframpBridgeError.quoteMismatch(
                field: "destinationAddress",
                expected: destinationAddress,
                actual: quote.destinationAddress
            )
        }
        guard quote.refundAddress == refundAddress else {
            throw OfframpBridgeError.quoteMismatch(
                field: "refundAddress",
                expected: refundAddress,
                actual: quote.refundAddress
            )
        }
        guard quote.originAssetId == originAssetId else {
            throw OfframpBridgeError.quoteMismatch(
                field: "originAsset",
                expected: originAssetId,
                actual: quote.originAssetId
            )
        }
        guard quote.destinationAssetId == destinationAssetId else {
            throw OfframpBridgeError.quoteMismatch(
                field: "destinationAsset",
                expected: destinationAssetId,
                actual: quote.destinationAssetId
            )
        }
    }

    static func validateRefund(
        _ quote: SwapQuote,
        requestedMicros: String,
        destinationAddress: String,
        refundAddress: String,
        originAssetId: String,
        destinationAssetId: String
    ) throws {
        let depositedMicros = NSDecimalNumber(decimal: quote.amountIn * 1_000_000).stringValue
        guard depositedMicros == requestedMicros else {
            throw OfframpBridgeError.quoteMismatch(
                field: "amountIn",
                expected: requestedMicros,
                actual: depositedMicros
            )
        }
        guard quote.destinationAddress == destinationAddress else {
            throw OfframpBridgeError.quoteMismatch(
                field: "destinationAddress",
                expected: destinationAddress,
                actual: quote.destinationAddress
            )
        }
        guard quote.refundAddress == refundAddress else {
            throw OfframpBridgeError.quoteMismatch(
                field: "refundAddress",
                expected: refundAddress,
                actual: quote.refundAddress
            )
        }
        guard quote.originAssetId == originAssetId else {
            throw OfframpBridgeError.quoteMismatch(
                field: "originAsset",
                expected: originAssetId,
                actual: quote.originAssetId
            )
        }
        guard quote.destinationAssetId == destinationAssetId else {
            throw OfframpBridgeError.quoteMismatch(
                field: "destinationAsset",
                expected: destinationAssetId,
                actual: quote.destinationAssetId
            )
        }
    }
}

enum OfframpBridgeError: LocalizedError {
    case missingAsset(String)
    case missingRefundAddress
    case missingTransactionId
    case quoteMismatch(field: String, expected: String, actual: String)
    case submissionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAsset(let name): return "1-Click does not currently list \(name)."
        case .missingRefundAddress: return "A private Zcash refund address could not be created."
        case .missingTransactionId: return "The Zcash deposit returned no transaction id."
        case .quoteMismatch(let field, let expected, let actual):
            return "Bridge quote \(field) mismatch (expected \(expected), got \(actual))."
        case .submissionFailed(let message): return "The Zcash deposit failed: \(message)"
        }
    }
}
