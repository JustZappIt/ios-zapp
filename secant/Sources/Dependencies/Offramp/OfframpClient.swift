// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

struct OfframpCorridor: Equatable, Identifiable, Sendable {
    let currencyCode: String
    let countryName: String
    let paymentRail: String
    let flag: String
    let symbol: String
    let precision: Int
    var id: String { currencyCode }
}

struct OfframpScanResult: Equatable, Sendable {
    let rawPayload: String
    let paymentAddress: String
    let fiatAmount: String?
}

struct OfframpQuoteModel: Equatable, Sendable {
    let currencyCode: String
    let fiatAmount: String
    let usdcMicros: String
    let usdcDisplay: String
    let sellRate: String
    let fixedFeeDisplay: String
    let baseBalanceDisplay: String
    let shortfallMicros: String
    let shortfallDisplay: String
    let canPayFromBase: Bool
    let canBridgeToBase: Bool
}

struct OfframpAccountModel: Equatable, Sendable {
    let address: String
    let balanceMicros: String?
    let balanceDisplay: String?
    let explorerURL: URL?
    let canBridgeToBase: Bool
    let canRefundToZec: Bool
}

struct OfframpProgressModel: Equatable, Sendable {
    let kind: String
    let step: String
    let title: String
    let detail: String?
    let orderId: String?
    let txHash: String?
    let bridgeDepositAddress: String?
    let isTerminal: Bool
    let isSuccess: Bool
}

struct OfframpHistoryModel: Equatable, Identifiable, Sendable {
    let id: String
    let status: String
    let orderType: String
    let currencyCode: String
    let usdcMicros: String
    let fiatMicros: String
    let placedAt: Date?
    let completedAt: Date?
    let cancelledAt: Date?
    let paymentAddress: String?
    let merchantAddress: String?
    let fixedFeeMicros: String?
}

enum OfframpClientError: LocalizedError, Equatable {
    case configuration(String)
    case invalidQR(String)
    case unsupportedAccount

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .invalidQR(let code): return "That QR is not valid for this payment method (\(code))."
        case .unsupportedAccount: return "P2P payments currently require a Zapp software wallet."
        }
    }
}

extension DependencyValues {
    var offramp: OfframpClient {
        get { self[OfframpClient.self] }
        set { self[OfframpClient.self] = newValue }
    }
}

@DependencyClient
struct OfframpClient {
    var corridors: @Sendable () async throws -> [OfframpCorridor]
    var parseQR: @Sendable (_ currencyCode: String, _ rawPayload: String) async throws -> OfframpScanResult
    var quote: @Sendable (_ currencyCode: String, _ fiatAmount: String) async throws -> OfframpQuoteModel
    var pay: @Sendable (
        _ quote: OfframpQuoteModel,
        _ payeeName: String?
    ) async throws -> AsyncStream<OfframpProgressModel>
    var resumePayment: @Sendable () async throws -> AsyncStream<OfframpProgressModel>
    var submitPaymentDetails: @Sendable (_ scan: OfframpScanResult) async throws -> Void
    var bridgeToBase: @Sendable (_ usdcMicros: String, _ resumeHandle: String?) async throws -> AsyncStream<OfframpProgressModel>
    var history: @Sendable () async throws -> [OfframpHistoryModel]
    var recoverFunds: @Sendable (_ orderId: String?) async throws -> AsyncStream<OfframpProgressModel>
    var hasCheckpoint: @Sendable () async throws -> Bool
    var checkpointCurrencyCode: @Sendable () async throws -> String?
    var discardCheckpoint: @Sendable () async throws -> Void
    var accountAddress: @Sendable () async throws -> String
    var accountSummary: @Sendable () async throws -> OfframpAccountModel
    var transactionURL: @Sendable (_ txHash: String) async throws -> URL?
}

extension OfframpClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        let paymentDetails = OfframpPaymentDetailsHost()
        return Self(
            corridors: {
                try await OfframpSession.shared.client().corridors().map(OfframpCorridor.init)
            },
            parseQR: { currency, payload in
                let parsed = try await OfframpSession.shared.client().parsePaymentQr(
                    currencyCode: currency,
                    rawPayload: payload
                )
                guard parsed.isValid, let address = parsed.paymentAddress else {
                    throw OfframpClientError.invalidQR(parsed.errorCode ?? "invalid_format")
                }
                return OfframpScanResult(rawPayload: payload, paymentAddress: address, fiatAmount: parsed.fiatAmount)
            },
            quote: { currency, amount in
                OfframpQuoteModel(try await OfframpSession.shared.client().quote(
                    currencyCode: currency,
                    fiatAmount: amount
                ))
            },
            pay: { quote, payeeName in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { return AsyncStream { $0.finish() } }
                let client = try await OfframpSession.shared.client()
                await paymentDetails.reset()
                let nativeQuote = try await client.quote(currencyCode: quote.currencyCode, fiatAmount: quote.fiatAmount)
                // Re-quote at commit time. This is the same drift guard as Android; never submit the
                // stale screen quote after the contract rate or fixed fee changes.
                let flow = client.pay(
                    quote: nativeQuote,
                    paymentDetailsProvider: paymentDetails,
                    payeeName: payeeName
                )
                return flow.offrampStream()
            },
            resumePayment: {
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { return AsyncStream { $0.finish() } }
                let client = try await OfframpSession.shared.client()
                await paymentDetails.reset()
                return client.resumePayment(paymentDetailsProvider: paymentDetails).offrampStream()
            },
            submitPaymentDetails: { scan in
                try await paymentDetails.submit(scan)
            },
            bridgeToBase: { micros, resume in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { return AsyncStream { $0.finish() } }
                let flow = try await OfframpSession.shared.client().bridgeToBase(
                    usdcMicros: micros,
                    resumeDepositAddress: resume
                )
                return flow.offrampStream()
            },
            history: {
                try await OfframpSession.shared.client().history().map(OfframpHistoryModel.init)
            },
            recoverFunds: { orderId in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { return AsyncStream { $0.finish() } }
                let flow = try await OfframpSession.shared.client().recoverFunds(orderId: orderId)
                return flow.offrampStream()
            },
            hasCheckpoint: {
                try await OfframpSession.shared.client().hasCheckpoint().boolValue
            },
            checkpointCurrencyCode: {
                try await OfframpSession.shared.client().checkpointCurrencyCode()
            },
            discardCheckpoint: {
                try await OfframpSession.shared.client().discardCheckpoint()
            },
            accountAddress: {
                try await OfframpSession.shared.client().accountAddress()
            },
            accountSummary: {
                OfframpAccountModel(try await OfframpSession.shared.client().accountSummary())
            },
            transactionURL: { hash in
                URL(string: try await OfframpSession.shared.client().transactionUrl(txHash: hash))
            }
        )
    }
}

private enum OfframpPaymentDetailsError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: return "The merchant payment-details request was cancelled."
        }
    }
}

/// One suspended request per payment. The shared engine calls this only after merchant acceptance;
/// the scanner resumes it with a locally validated QR payload.
private final class OfframpPaymentDetailsHost: NSObject, AppleOfframpPaymentDetailsProvider, @unchecked Sendable {
    private let worker = OfframpPaymentDetailsWorker()

    func __requestPaymentDetails(
        orderId: String,
        currencyCode: String,
        fiatAmount: String,
        completionHandler: @escaping @Sendable (AppleOfframpPaymentDetails?, Error?) -> Void
    ) {
        Task {
            do { completionHandler(try await worker.waitForDetails(), nil) }
            catch { completionHandler(nil, error) }
        }
    }

    func submit(_ scan: OfframpScanResult) async throws {
        await worker.submit(scan)
    }

    func reset() async {
        await worker.reset()
    }
}

private actor OfframpPaymentDetailsWorker {
    private var continuation: CheckedContinuation<AppleOfframpPaymentDetails, Error>?
    private var pending: AppleOfframpPaymentDetails?

    func waitForDetails() async throws -> AppleOfframpPaymentDetails {
        if let pending {
            self.pending = nil
            return pending
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func submit(_ scan: OfframpScanResult) {
        let details = AppleOfframpPaymentDetails(
            rawPayload: scan.rawPayload,
            paymentAddress: scan.paymentAddress,
            fiatAmount: scan.fiatAmount
        )
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: details)
        } else {
            pending = details
        }
    }

    func reset() {
        continuation?.resume(throwing: OfframpPaymentDetailsError.cancelled)
        continuation = nil
        pending = nil
    }
}

private actor OfframpSession {
    static let shared = OfframpSession()

    private var cachedClient: AppleOfframpClient?
    private var cachedWalletIdentity: String?

    func client() async throws -> AppleOfframpClient {
        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.swapAndPay) var swapAndPay
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer
        @Dependency(\.mnemonic) var mnemonic
        @Dependency(\.derivationTool) var derivationTool
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let account = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using P2P payments.")
        }
        guard account.vendor == .zcash else { throw OfframpClientError.unsupportedAccount }
        let accountID = account.id.id.map { String(format: "%02x", $0) }.joined()
        let isTestnet = environment.network().networkType == .testnet
        // Account UUID alone is not a sufficient wallet-lifecycle boundary. Include the SDK seed
        // fingerprint so a delete + restore in the same process can never retain the prior
        // wallet's Base owner/client. The mnemonic itself is never used as a cache key.
        let seedFingerprint = account.seedFingerprint?.map { String(format: "%02x", $0) }.joined() ?? ""
        let walletIdentity = "\(accountID):\(seedFingerprint):\(isTestnet ? "testnet" : "mainnet")"
        if cachedWalletIdentity == walletIdentity, let cachedClient { return cachedClient }

        guard let pimlicoKey = PartnerKeys.p2pPimlicoApiKey, !pimlicoKey.isEmpty else {
            throw OfframpClientError.configuration("P2P payments are not configured in PartnerKeys.plist.")
        }
        // The KMP facade derives the Base owner directly from this active Zcash wallet mnemonic
        // at m/44'/60'/0'/0/0, matching Android. No separate Base seed or private key is stored.
        let seedPhrase = try walletStorage.exportWallet().seedPhrase.value()
        let storage = try OfframpEncryptedStorage(account: account.account, walletStorage: walletStorage)
        let bridge: AppleOfframpBridge? = isTestnet ? nil : OfframpNearBridge(
            account: account,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer,
            walletStorage: walletStorage,
            mnemonic: mnemonic,
            derivationTool: derivationTool,
            environment: environment
        )
        let client = try await AppleOfframpClient.companion.create(
            networkName: isTestnet ? "sepolia" : "mainnet",
            seedPhrase: seedPhrase,
            pimlicoApiKey: pimlicoKey,
            storage: storage,
            bridge: bridge,
            rpcUrl: isTestnet ? nil : PartnerKeys.p2pRpcBaseMainnet,
            subgraphUrl: isTestnet ? nil : PartnerKeys.p2pSubgraphMainnet,
            sponsorshipPolicyId: PartnerKeys.p2pSponsorshipPolicyId
        )
        cachedClient?.close()
        cachedClient = client
        cachedWalletIdentity = walletIdentity
        return client
    }
}

private extension OfframpCorridor {
    init(_ value: ApplePaymentCorridor) {
        self.init(
            currencyCode: value.currencyCode,
            countryName: value.countryName,
            paymentRail: value.paymentRail,
            flag: value.flag,
            symbol: value.symbol,
            precision: Int(value.precision)
        )
    }
}

private extension OfframpQuoteModel {
    init(_ value: AppleOfframpQuote) {
        self.init(
            currencyCode: value.currencyCode,
            fiatAmount: value.fiatAmount,
            usdcMicros: value.usdcMicros,
            usdcDisplay: value.usdcDisplay,
            sellRate: value.sellRate,
            fixedFeeDisplay: value.fixedFeeDisplay,
            baseBalanceDisplay: value.baseBalanceDisplay,
            shortfallMicros: value.shortfallMicros,
            shortfallDisplay: value.shortfallDisplay,
            canPayFromBase: value.canPayFromBase,
            canBridgeToBase: value.canBridgeToBase
        )
    }
}

private extension OfframpAccountModel {
    init(_ value: AppleOfframpAccountSummary) {
        self.init(
            address: value.address,
            balanceMicros: value.balanceMicros,
            balanceDisplay: value.balanceDisplay,
            explorerURL: URL(string: value.explorerUrl),
            canBridgeToBase: value.canBridgeToBase,
            canRefundToZec: value.canRefundToZec
        )
    }
}

private extension OfframpProgressModel {
    init(_ value: AppleOfframpStatus) {
        self.init(
            kind: value.kind,
            step: value.step,
            title: value.title,
            detail: value.detail,
            orderId: value.orderId,
            txHash: value.txHash,
            bridgeDepositAddress: value.bridgeDepositAddress,
            isTerminal: value.isTerminal,
            isSuccess: value.isSuccess
        )
    }
}

private extension OfframpHistoryModel {
    init(_ value: AppleOfframpHistoryItem) {
        self.init(
            id: value.orderId,
            status: value.status,
            orderType: value.orderType,
            currencyCode: value.currencyCode,
            usdcMicros: value.usdcMicros,
            fiatMicros: value.fiatMicros,
            placedAt: value.placedAtEpochSeconds?.date,
            completedAt: value.completedAtEpochSeconds?.date,
            cancelledAt: value.cancelledAtEpochSeconds?.date,
            paymentAddress: value.paymentAddress,
            merchantAddress: value.merchantAddress,
            fixedFeeMicros: value.fixedFeeMicros
        )
    }
}

private extension KotlinLong {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(int64Value)) }
}

private extension SkieSwiftFlow where T == AppleOfframpStatus {
    func offrampStream() -> AsyncStream<OfframpProgressModel> {
        AsyncStream { continuation in
            let task = Task {
                for await status in self {
                    guard !Task.isCancelled else { break }
                    continuation.yield(OfframpProgressModel(status))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
