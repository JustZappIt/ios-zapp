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

    var type: OfframpHistoryOrderType? { OfframpHistoryOrderType(rawValue: orderType.uppercased()) }
    var canRecoverEscrow: Bool { status.uppercased() == "CANCELLED" && type != .buy }
}

enum OfframpHistoryOrderType: String, Equatable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
    case pay = "PAY"

    var label: String {
        switch self {
        case .buy: return String(localizable: .offrampHistoryTypeBuy)
        case .sell: return String(localizable: .offrampHistoryTypeSell)
        case .pay: return String(localizable: .offrampHistoryTypePay)
        }
    }
}

enum OfframpClientError: LocalizedError, Equatable {
    case configuration(String)
    case invalidQR(String)
    case unsupportedAccount
    case authenticationCancelled
    case staleQuote

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .invalidQR(let code): return "That QR is not valid for this payment method (\(code))."
        case .unsupportedAccount: return "P2P payments currently require a Zapp software wallet."
        case .authenticationCancelled: return "Authentication was cancelled. No payment was submitted."
        case .staleQuote: return "The payment quote changed. Review the updated amount before trying again."
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
    var previewTopUp: @Sendable (_ usdcMicros: String) async throws -> OfframpBridgePreview
    var history: @Sendable () async throws -> [OfframpHistoryModel]
    var recoverFunds: @Sendable (_ orderId: String?) async throws -> AsyncStream<OfframpProgressModel>
    var previewRefund: @Sendable () async throws -> OfframpBridgePreview
    var hasCheckpoint: @Sendable () async throws -> Bool
    var checkpointCurrencyCode: @Sendable () async throws -> String?
    var discardCheckpoint: @Sendable () async throws -> Void
    var hasTopUpCheckpoint: @Sendable () async throws -> Bool
    var topUpCheckpointMicros: @Sendable () async throws -> String?
    var discardTopUpCheckpoint: @Sendable () async throws -> Void
    var accountAddress: @Sendable () async throws -> String
    var accountSummary: @Sendable () async throws -> OfframpAccountModel
    var transactionURL: @Sendable (_ txHash: String) async throws -> URL?
    var invalidateSession: @Sendable () async -> Void

    /// The owner key behind the P2P cash-out account, for the profile's reveal surface.
    /// See `OfframpWalletKey.swift` — the secret never leaves a `RedactableString`.
    var exportWalletKey: @Sendable () async throws -> OfframpWalletKey
}

extension OfframpClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        let paymentDetails = OfframpPaymentDetailsHost()
        let quoteAuthorization = OfframpQuoteAuthorization()
        return Self(
            corridors: {
                try await OfframpSession.shared.client().corridors().map(OfframpCorridor.init)
            },
            parseQR: { currency, payload in
                guard payload.utf8.count <= 16_384 else {
                    throw OfframpClientError.invalidQR("payload_too_large")
                }
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
                let native = try await OfframpSession.shared.client().quote(
                    currencyCode: currency,
                    fiatAmount: amount
                )
                let model = OfframpQuoteModel(native)
                quoteAuthorization.authorize(native, model: model)
                return model
            },
            pay: { quote, payeeName in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                let client = try await OfframpSession.shared.client()
                await paymentDetails.reset()
                guard let nativeQuote = quoteAuthorization.consume(matching: quote) else {
                    throw OfframpClientError.staleQuote
                }
                let flow = client.pay(
                    quote: nativeQuote,
                    paymentDetailsProvider: paymentDetails,
                    payeeName: payeeName
                )
                return flow.offrampStream()
            },
            resumePayment: {
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                let client = try await OfframpSession.shared.client()
                await paymentDetails.reset()
                return client.resumePayment(paymentDetailsProvider: paymentDetails).offrampStream()
            },
            submitPaymentDetails: { scan in
                try await paymentDetails.submit(scan)
            },
            bridgeToBase: { micros, resume in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                let flow = try await OfframpSession.shared.client().bridgeToBase(
                    usdcMicros: micros,
                    resumeDepositAddress: resume
                )
                return flow.offrampStream()
            },
            previewTopUp: { micros in
                try await OfframpSession.shared.previewTopUp(usdcMicros: micros)
            },
            history: {
                try await OfframpSession.shared.client().history().map(OfframpHistoryModel.init)
            },
            recoverFunds: { orderId in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                let flow = try await OfframpSession.shared.client().recoverFunds(orderId: orderId)
                return flow.offrampStream()
            },
            previewRefund: {
                try await OfframpSession.shared.previewRefund()
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
            hasTopUpCheckpoint: {
                try await OfframpSession.shared.client().hasTopUpCheckpoint().boolValue
            },
            topUpCheckpointMicros: {
                try await OfframpSession.shared.client().topUpCheckpointMicros()
            },
            discardTopUpCheckpoint: {
                try await OfframpSession.shared.client().discardTopUpCheckpoint()
            },
            accountAddress: {
                try await OfframpSession.shared.client().accountAddress()
            },
            accountSummary: {
                OfframpAccountModel(try await OfframpSession.shared.client().accountSummary())
            },
            transactionURL: { hash in
                URL(string: try await OfframpSession.shared.client().transactionUrl(txHash: hash))
            },
            invalidateSession: {
                await paymentDetails.reset()
                quoteAuthorization.reset()
                await OfframpSession.shared.invalidate()
            },
            exportWalletKey: {
                try OfframpWalletKey.derive()
            }
        )
    }
}

private final class OfframpQuoteAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var authorized: (model: OfframpQuoteModel, native: AppleOfframpQuote)?

    func authorize(_ native: AppleOfframpQuote, model: OfframpQuoteModel) {
        lock.withLock { authorized = (model, native) }
    }

    func consume(matching model: OfframpQuoteModel) -> AppleOfframpQuote? {
        lock.withLock {
            guard let authorized, authorized.model == model else { return nil }
            self.authorized = nil
            return authorized.native
        }
    }

    func reset() {
        lock.withLock { authorized = nil }
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

/// One wallet-scoped P2P session. Cash-out, buy, refund and top-up all move USDC from the same
/// Base smart account, so every rail is built on one `AppleBaseAccount` and therefore shares the
/// single ERC-4337 submitter that account's nonce cursor lives in.
///
/// Construction is single-flight. These builders suspend long before they can cache anything, and
/// an actor admits other callers while they do, so caching the in-flight task — not just its
/// result — is what keeps a screen's concurrent loads from each building their own client.
actor OfframpSession {
    static let shared = OfframpSession()

    private struct OfframpRail {
        let client: AppleOfframpClient
        let bridge: OfframpNearBridge?

        func release() { bridge?.invalidate() }
    }

    private struct OnrampRail {
        let client: AppleOnrampClient
        let gateway: OnrampZecSwapGateway?

        func release() { gateway?.invalidate() }
    }

    private var account: AppleBaseAccount?
    private var offramp: OfframpRail?
    private var onramp: OnrampRail?
    private var accountTask: Task<AppleBaseAccount, Error>?
    private var offrampTask: Task<OfframpRail, Error>?
    private var onrampTask: Task<OnrampRail, Error>?
    private var walletIdentity: String?
    private var generation = 0

    func client() async throws -> AppleOfframpClient {
        try await offrampRail().client
    }

    func onrampClient() async throws -> AppleOnrampClient {
        try await onrampRail().client
    }

    /// Releases everything this session adopted. A build still in flight is cancelled and releases
    /// itself when `adopt` turns it away, so nothing is ever torn down twice.
    func invalidate() {
        generation &+= 1
        walletIdentity = nil
        accountTask?.cancel()
        offrampTask?.cancel()
        onrampTask?.cancel()
        accountTask = nil
        offrampTask = nil
        onrampTask = nil
        onramp?.release()
        offramp?.release()
        onramp = nil
        offramp = nil
        // The account holds the HTTP client and the Base owner key both rails borrow, so it is last.
        account?.close()
        account = nil
    }

    /// Takes ownership of a finished build, or refuses it because the session has moved on to
    /// another wallet since it started. Refusing is what makes the builder release it instead.
    private func adopt(_ built: AppleBaseAccount, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        account = built
        return true
    }

    private func adopt(_ built: OfframpRail, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        offramp = built
        return true
    }

    private func adopt(_ built: OnrampRail, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        onramp = built
        return true
    }

    private func baseAccount() async throws -> AppleBaseAccount {
        let identity = try walletScope()
        // Cross the wallet/network boundary before deriving anything new. This zeroizes the old
        // Base key and cancels bridge work even if the new setup then fails.
        if identity != walletIdentity { invalidate() }
        walletIdentity = identity
        if let accountTask { return try await accountTask.value }

        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let pimlicoKey = PartnerKeys.p2pPimlicoApiKey, !pimlicoKey.isEmpty else {
            throw OfframpClientError.configuration("P2P payments are not configured in PartnerKeys.plist.")
        }
        let isTestnet = environment.network().networkType == .testnet
        // The KMP facade derives the Base owner directly from this active Zcash wallet mnemonic
        // at m/44'/60'/0'/0/0, matching Android. No separate Base seed or private key is stored.
        let seedPhrase = try walletStorage.exportWallet().seedPhrase.value()
        let generation = self.generation
        let task = Task {
            let built = try await AppleBaseAccount.companion.create(
                networkName: isTestnet ? "sepolia" : "mainnet",
                seedPhrase: seedPhrase,
                pimlicoApiKey: pimlicoKey,
                rpcUrl: isTestnet ? nil : PartnerKeys.p2pRpcBaseMainnet,
                subgraphUrl: isTestnet ? nil : PartnerKeys.p2pSubgraphMainnet,
                sponsorshipPolicyId: PartnerKeys.p2pSponsorshipPolicyId
            )
            guard self.adopt(built, generation: generation) else {
                built.close()
                throw CancellationError()
            }
            return built
        }
        accountTask = task
        return try await value(of: task) { if self.accountTask == task { self.accountTask = nil } }
    }

    private func offrampRail() async throws -> OfframpRail {
        let base = try await baseAccount()
        if let offrampTask { return try await offrampTask.value }

        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.swapAndPay) var swapAndPay
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer
        @Dependency(\.mnemonic) var mnemonic
        @Dependency(\.derivationTool) var derivationTool
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let wallet = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using P2P payments.")
        }
        let storage = try OfframpEncryptedStorage(account: wallet.account, walletStorage: walletStorage)
        let bridge: OfframpNearBridge? = environment.network().networkType == .testnet ? nil : OfframpNearBridge(
            account: wallet,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer,
            walletStorage: walletStorage,
            mnemonic: mnemonic,
            derivationTool: derivationTool,
            environment: environment
        )
        let generation = self.generation
        let task = Task {
            let built = OfframpRail(
                client: try await AppleOfframpClient.companion.create(
                    account: base,
                    storage: storage,
                    bridge: bridge
                ),
                bridge: bridge
            )
            guard self.adopt(built, generation: generation) else {
                built.release()
                throw CancellationError()
            }
            return built
        }
        offrampTask = task
        return try await value(of: task) { if self.offrampTask == task { self.offrampTask = nil } }
    }

    private func onrampRail() async throws -> OnrampRail {
        let base = try await baseAccount()
        if let onrampTask { return try await onrampTask.value }

        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.swapAndPay) var swapAndPay
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let wallet = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before buying ZEC.")
        }
        guard let baseURL = PartnerKeys.p2pOnrampBaseUrl, !baseURL.isEmpty else {
            throw OfframpClientError.configuration("P2P buying is not configured in PartnerKeys.plist.")
        }
        let storage = try OnrampEncryptedStorage(account: wallet.account, walletStorage: walletStorage)
        let gateway: OnrampZecSwapGateway? = environment.network().networkType == .testnet ? nil : OnrampZecSwapGateway(
            account: wallet,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer
        )
        let generation = self.generation
        let task = Task {
            let built = OnrampRail(
                client: try await AppleOnrampClient.companion.create(
                    account: base,
                    onrampBaseUrl: baseURL,
                    storage: storage,
                    deviceSignals: OnrampDeviceSignals(),
                    onrampAppId: "zapp",
                    swapGateway: gateway,
                    useFakeDeliveryDriver: false
                ),
                gateway: gateway
            )
            guard self.adopt(built, generation: generation) else {
                built.release()
                throw CancellationError()
            }
            return built
        }
        onrampTask = task
        return try await value(of: task) { if self.onrampTask == task { self.onrampTask = nil } }
    }

    /// Awaits a build, dropping a failed one from the cache so the next caller may try again.
    private func value<T>(of task: Task<T, Error>, onFailure evict: () -> Void) async throws -> T {
        do {
            return try await task.value
        } catch {
            evict()
            throw error
        }
    }

    /// The wallet lifetime a session belongs to. The account UUID alone is not a sufficient
    /// boundary, so the SDK seed fingerprint is included: a delete and restore in the same process
    /// can then never retain the prior wallet's Base owner. The mnemonic is never a cache key.
    private func walletScope() throws -> String {
        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let account = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using P2P payments.")
        }
        guard account.vendor == .zcash else { throw OfframpClientError.unsupportedAccount }
        guard let fingerprint = account.seedFingerprint, !fingerprint.isEmpty else {
            throw OfframpClientError.configuration("The active wallet identity is unavailable. Reopen the wallet before using P2P payments.")
        }
        let accountID = account.id.id.map { String(format: "%02x", $0) }.joined()
        let seedFingerprint = fingerprint.map { String(format: "%02x", $0) }.joined()
        let network = environment.network().networkType == .testnet ? "testnet" : "mainnet"
        return "\(accountID):\(seedFingerprint):\(network)"
    }

    func previewTopUp(usdcMicros: String) async throws -> OfframpBridgePreview {
        let rail = try await offrampRail()
        guard let amount = Decimal(string: usdcMicros), amount > 0, amount <= 100_000_000 else {
            throw OfframpClientError.configuration("Base top-ups are limited to 100 USDC.")
        }
        if try await rail.client.hasTopUpCheckpoint().boolValue {
            guard try await rail.client.topUpCheckpointMicros() == usdcMicros else {
                throw OfframpClientError.configuration(
                    "A different Base top-up is already in progress. Resume or discard it first."
                )
            }
            return OfframpBridgePreview(
                sourceAmount: "Previously authorized",
                sourceAsset: "ZEC bridge",
                destinationAmount: OfframpSession.usdcDisplay(usdcMicros),
                destinationAsset: "USDC on Base",
                networkFee: nil,
                estimatedSeconds: 0
            )
        }
        guard let bridge = rail.bridge else {
            throw OfframpClientError.configuration("Automatic ZEC bridging is unavailable on this network.")
        }
        return try await bridge.previewTopUp(
            accountAddress: try await rail.client.accountAddress(),
            usdcMicros: usdcMicros
        )
    }

    func previewRefund() async throws -> OfframpBridgePreview {
        let rail = try await offrampRail()
        guard let bridge = rail.bridge else {
            throw OfframpClientError.configuration("Automatic Base refunds are unavailable on this network.")
        }
        let account = try await rail.client.accountSummary()
        guard let micros = account.balanceMicros, let value = Decimal(string: micros), value > 0 else {
            guard account.canRefundToZec else {
                throw OfframpClientError.configuration("The Base USDC balance could not be verified for refund.")
            }
            return OfframpBridgePreview(
                sourceAmount: "Previously authorized",
                sourceAsset: "Base refund",
                destinationAmount: "Pending",
                destinationAsset: "ZEC",
                networkFee: nil,
                estimatedSeconds: 0
            )
        }
        return try await bridge.previewRefund(
            accountAddress: account.address,
            usdcMicros: micros
        )
    }

    private static func usdcDisplay(_ micros: String) -> String {
        guard let value = Decimal(string: micros) else { return micros }
        return NSDecimalNumber(decimal: value / 1_000_000).stringValue
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
