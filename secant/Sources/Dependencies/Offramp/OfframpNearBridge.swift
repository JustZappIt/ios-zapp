// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp
@preconcurrency import ZcashLightClientKit

struct OfframpBridgePreview: Equatable, Sendable {
    let sourceAmount: String
    let sourceAsset: String
    let destinationAmount: String
    let destinationAsset: String
    let networkFee: String?
    let estimatedSeconds: Int
}

/// iOS wallet/1-Click half of the shared bridge contract. Preparing is read-only; execute sends the
/// already-persisted quote exactly once; resume only polls the existing deposit address.
final class OfframpNearBridge: NSObject, AppleOfframpBridge, @unchecked Sendable {
    private let worker: OfframpNearBridgeWorker
    private let tasks = OfframpBridgeTaskRegistry()

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
        guard tasks.launch({ [worker] in
            do { completionHandler(try await worker.prepare(accountAddress: accountAddress, usdcMicros: usdcMicros), nil) }
            catch { completionHandler(nil, error) }
        }) else { return completionHandler(nil, CancellationError()) }
    }

    func __execute(
        depositAddress: String,
        completionHandler: @escaping @Sendable (AppleBridgeExecution?, Error?) -> Void
    ) {
        guard tasks.launch({ [worker] in
            do { completionHandler(try await worker.execute(depositAddress: depositAddress), nil) }
            catch { completionHandler(nil, error) }
        }) else { return completionHandler(nil, CancellationError()) }
    }

    func __resume(
        depositAddress: String,
        completionHandler: @escaping @Sendable (AppleBridgeExecution?, Error?) -> Void
    ) {
        guard tasks.launch({ [worker] in completionHandler(await worker.poll(depositAddress: depositAddress), nil) }) else {
            return completionHandler(nil, CancellationError())
        }
    }

    func __prepareRefund(
        accountAddress: String,
        usdcMicros: String,
        completionHandler: @escaping @Sendable (String?, Error?) -> Void
    ) {
        guard tasks.launch({ [worker] in
            do {
                completionHandler(
                    try await worker.prepareRefund(accountAddress: accountAddress, usdcMicros: usdcMicros),
                    nil
                )
            } catch { completionHandler(nil, error) }
        }) else { return completionHandler(nil, CancellationError()) }
    }

    func invalidate() {
        tasks.invalidate()
        Task { await worker.invalidate() }
    }

    func previewTopUp(accountAddress: String, usdcMicros: String) async throws -> OfframpBridgePreview {
        try await worker.previewTopUp(accountAddress: accountAddress, usdcMicros: usdcMicros)
    }

    func previewRefund(accountAddress: String, usdcMicros: String) async throws -> OfframpBridgePreview {
        try await worker.previewRefund(accountAddress: accountAddress, usdcMicros: usdcMicros)
    }
}

private final class OfframpBridgeTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var running: [UUID: Task<Void, Never>] = [:]
    private var isInvalidated = false

    @discardableResult
    func launch(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        let id = UUID()
        return lock.withLock {
            guard !isInvalidated else { return false }
            running[id] = Task { [weak self] in
                await operation()
                self?.remove(id)
            }
            return true
        }
    }

    func invalidate() {
        let tasks = lock.withLock {
            isInvalidated = true
            let tasks = Array(running.values)
            running.removeAll()
            return tasks
        }
        tasks.forEach { $0.cancel() }
    }

    private func remove(_ id: UUID) {
        lock.withLock { running[id] = nil }
    }
}

private actor OfframpNearBridgeWorker {
    private struct PreparedBridge {
        let quote: SwapQuote
        let proposal: Proposal
    }

    private struct AuthorizedBridge {
        let quote: SwapQuote
        let proposal: Proposal
        let expiresAt: Date
    }

    private struct AuthorizedRefund {
        let quote: SwapQuote
        let expiresAt: Date
    }

    private let account: WalletAccount
    private let swapAndPay: SwapAndPayClient
    private let sdkSynchronizer: SDKSynchronizerClient
    private let walletStorage: WalletStorageClient
    private let mnemonic: MnemonicClient
    private let derivationTool: DerivationToolClient
    private let environment: ZcashSDKEnvironment
    private var prepared: [String: PreparedBridge] = [:]
    private var authorizedTopUps: [String: AuthorizedBridge] = [:]
    private var authorizedRefunds: [String: AuthorizedRefund] = [:]
    private var isInvalidated = false

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
        try requireActive()
        let key = authorizationKey(accountAddress: accountAddress, usdcMicros: usdcMicros)
        guard let authorization = authorizedTopUps.removeValue(forKey: key), authorization.expiresAt > Date() else {
            throw OfframpBridgeError.previewRequired
        }
        prepared[authorization.quote.depositAddress] = PreparedBridge(
            quote: authorization.quote,
            proposal: authorization.proposal
        )
        return authorization.quote.depositAddress
    }

    func previewTopUp(accountAddress: String, usdcMicros: String) async throws -> OfframpBridgePreview {
        try requireActive()
        let assets = try await assets()
        try requireActive()
        let refundAddress = try await privateAddress()
        try requireActive()
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
        try requireActive()
        try OfframpBridgeQuoteValidator.validate(
            quote,
            requestedMicros: usdcMicros,
            destinationAddress: accountAddress,
            refundAddress: refundAddress,
            originAssetId: assets.zec.assetId,
            destinationAssetId: assets.usdc.assetId
        )
        let recipient = try Recipient(quote.depositAddress, network: environment.network().networkType)
        let amount = Zatoshi(NSDecimalNumber(decimal: quote.amountIn).int64Value)
        let balances = try await sdkSynchronizer.getAccountsBalances()
        try requireActive()
        guard let balance = balances[account.id] else { throw OfframpBridgeError.balanceUnavailable }
        let spendable = balance.saplingBalance.spendableValue + balance.orchardBalance.spendableValue
        // Check the quoted principal before asking the SDK to build a proposal. Otherwise an empty
        // wallet can fail inside the SDK bridge as an opaque interop error before we can present the
        // Android-style spendable-balance validation.
        guard amount.amount <= spendable.amount else {
            throw OfframpBridgeError.insufficientSpendableBalance(spendable.decimalString())
        }
        let proposal = try await sdkSynchronizer.proposeTransfer(account.id, recipient, amount, nil)
        try requireActive()
        let fee = proposal.totalFeeRequired()
        guard amount.amount <= Int64.max - fee.amount, amount.amount + fee.amount <= spendable.amount else {
            throw OfframpBridgeError.insufficientSpendableBalance(spendable.decimalString())
        }
        let key = authorizationKey(accountAddress: accountAddress, usdcMicros: usdcMicros)
        authorizedTopUps[key] = AuthorizedBridge(
            quote: quote,
            proposal: proposal,
            expiresAt: Date().addingTimeInterval(Self.authorizationLifetime)
        )
        return OfframpBridgePreview(
            sourceAmount: amount.decimalString(),
            sourceAsset: "ZEC",
            destinationAmount: NSDecimalNumber(decimal: quote.amountOut).stringValue,
            destinationAsset: "USDC on Base",
            networkFee: fee.decimalString(),
            estimatedSeconds: Int(quote.timeEstimate)
        )
    }

    func execute(depositAddress: String) async throws -> AppleBridgeExecution {
        try requireActive()
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

        try Task.checkCancellation()
        try requireActive()
        let storedWallet = try walletStorage.exportWallet()
        let seedBytes = try mnemonic.toSeed(storedWallet.seedPhrase.value())
        let spendingKey = try derivationTool.deriveSpendingKey(
            seedBytes,
            accountIndex,
            environment.network().networkType
        )
        try Task.checkCancellation()
        try requireActive()
        let result = try await sdkSynchronizer.createAndSubmitProposedTransactions(bridge.proposal, spendingKey)
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
        try await swapAndPay.submitDepositTxId(txId, depositAddress)
        return await poll(depositAddress: depositAddress)
    }

    func prepareRefund(accountAddress: String, usdcMicros: String) async throws -> String {
        try requireActive()
        let key = authorizationKey(accountAddress: accountAddress, usdcMicros: usdcMicros)
        guard let authorization = authorizedRefunds.removeValue(forKey: key), authorization.expiresAt > Date() else {
            throw OfframpBridgeError.previewRequired
        }
        return authorization.quote.depositAddress
    }

    func previewRefund(accountAddress: String, usdcMicros: String) async throws -> OfframpBridgePreview {
        try requireActive()
        let assets = try await assets()
        try requireActive()
        let zecAddress = try await privateAddress()
        try requireActive()
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
        try requireActive()
        try OfframpBridgeQuoteValidator.validateRefund(
            quote,
            requestedMicros: usdcMicros,
            destinationAddress: zecAddress,
            refundAddress: accountAddress,
            originAssetId: assets.usdc.assetId,
            destinationAssetId: assets.zec.assetId
        )
        guard quote.amountOut > 0 else { throw OfframpBridgeError.zeroOutput }
        let key = authorizationKey(accountAddress: accountAddress, usdcMicros: usdcMicros)
        authorizedRefunds[key] = AuthorizedRefund(
            quote: quote,
            expiresAt: Date().addingTimeInterval(Self.authorizationLifetime)
        )
        return OfframpBridgePreview(
            sourceAmount: NSDecimalNumber(decimal: quote.amountIn).stringValue,
            sourceAsset: "USDC on Base",
            destinationAmount: NSDecimalNumber(decimal: quote.amountOut).stringValue,
            destinationAsset: "ZEC",
            networkFee: nil,
            estimatedSeconds: Int(quote.timeEstimate)
        )
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

    func invalidate() {
        isInvalidated = true
        prepared.removeAll()
        authorizedTopUps.removeAll()
        authorizedRefunds.removeAll()
    }

    private func requireActive() throws {
        guard !isInvalidated else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func authorizationKey(accountAddress: String, usdcMicros: String) -> String {
        "\(accountAddress.lowercased()):\(usdcMicros)"
    }

    private static let authorizationLifetime: TimeInterval = 120

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
    case previewRequired
    case balanceUnavailable
    case insufficientSpendableBalance(String)
    case zeroOutput

    var errorDescription: String? {
        switch self {
        case .missingAsset(let name): return "1-Click does not currently list \(name)."
        case .missingRefundAddress: return "A private Zcash refund address could not be created."
        case .missingTransactionId: return "The Zcash deposit returned no transaction id."
        case .quoteMismatch(let field, let expected, let actual):
            return "Bridge quote \(field) mismatch (expected \(expected), got \(actual))."
        case .submissionFailed(let message): return "The Zcash deposit failed: \(message)"
        case .previewRequired: return "The bridge quote expired or was not reviewed. Review it again before continuing."
        case .balanceUnavailable: return "The spendable ZEC balance could not be verified."
        case .insufficientSpendableBalance(let spendable):
            return "Not enough ZEC. Your spendable balance is \(spendable) ZEC."
        case .zeroOutput: return "The bridge quote would return no ZEC."
        }
    }
}
