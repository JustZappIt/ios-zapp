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
    let balanceMicros: String
    let balanceDisplay: String
    let explorerURL: URL?
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
        _ scan: OfframpScanResult,
        _ payeeName: String?
    ) async throws -> AsyncStream<OfframpProgressModel>
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
        Self(
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
            pay: { quote, scan, payeeName in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { return AsyncStream { $0.finish() } }
                let client = try await OfframpSession.shared.client()
                let nativeQuote = try await client.quote(currencyCode: quote.currencyCode, fiatAmount: quote.fiatAmount)
                // Re-quote at commit time. This is the same drift guard as Android; never submit the
                // stale screen quote after the contract rate or fixed fee changes.
                let flow = client.pay(
                    quote: nativeQuote,
                    rawPayload: scan.rawPayload,
                    paymentAddress: scan.paymentAddress,
                    payeeName: payeeName
                )
                return flow.offrampStream()
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

private actor OfframpSession {
    static let shared = OfframpSession()

    private var cachedClient: AppleOfframpClient?
    private var cachedAccountID: String?

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
        if cachedAccountID == accountID, let cachedClient { return cachedClient }

        guard let pimlicoKey = PartnerKeys.p2pPimlicoApiKey, !pimlicoKey.isEmpty else {
            throw OfframpClientError.configuration("P2P payments are not configured in PartnerKeys.plist.")
        }
        let seedPhrase = try walletStorage.exportWallet().seedPhrase.value()
        let isTestnet = environment.network().networkType == .testnet
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
        cachedAccountID = accountID
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
