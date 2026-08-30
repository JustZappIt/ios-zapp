// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

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

    /// App-lifetime owner of Peer's running work. It outlives every screen, so it is created once
    /// and told which client to use rather than rebuilt with the rails.
    let peerRunner = PeerCashOutRunner()

    private var account: AppleBaseAccount?
    private var offramp: OfframpRail?
    private var onramp: OnrampRail?
    private var peer: ApplePeerCashOutClient?
    private var accountTask: Task<AppleBaseAccount, Error>?
    private var offrampTask: Task<OfframpRail, Error>?
    private var onrampTask: Task<OnrampRail, Error>?
    private var peerTask: Task<ApplePeerCashOutClient, Error>?
    private var walletIdentity: String?
    private var generation = 0

    func client() async throws -> AppleOfframpClient {
        try await offrampRail().client
    }

    func onrampClient() async throws -> AppleOnrampClient {
        try await onrampRail().client
    }

    func peerClient() async throws -> ApplePeerCashOutClient {
        let base = try await baseAccount()
        if let peerTask { return try await peerTask.value }

        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage

        guard let wallet = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using Peer cash-out.")
        }
        // Peer shares the off-ramp's encrypted file: both rails spend from one Base smart account,
        // so their records are read and written together and a wallet reset clears them together.
        let storage = try OfframpEncryptedStorage(account: wallet.account, walletStorage: walletStorage)
        let generation = self.generation
        let task = Task {
            let built = try await ApplePeerCashOutClient.companion.create(account: base, storage: storage)
            guard self.adopt(built, generation: generation) else { throw CancellationError() }
            // Handing the client over is what starts recovery: the runner picks up the attempts a
            // previous process left unfinished and reconciles the ones that already settled.
            await self.peerRunner.bind(built)
            return built
        }
        peerTask = task
        return try await value(of: task) { if self.peerTask == task { self.peerTask = nil } }
    }

    /// Releases everything this session adopted. A build still in flight is cancelled and releases
    /// itself when `adopt` turns it away, so nothing is ever torn down twice.
    ///
    /// Peer's runner is cancelled *and joined* before anything else is released, because callers
    /// invalidate immediately before erasing wallet-scoped storage: merely cancelling would let an
    /// in-flight status write a recovery checkpoint into a file the wipe has already cleared.
    func invalidate() async {
        generation &+= 1
        walletIdentity = nil
        await peerRunner.reset()
        accountTask?.cancel()
        offrampTask?.cancel()
        onrampTask?.cancel()
        peerTask?.cancel()
        accountTask = nil
        offrampTask = nil
        onrampTask = nil
        peerTask = nil
        onramp?.release()
        offramp?.release()
        onramp = nil
        offramp = nil
        peer = nil
        // The account holds the HTTP client and the Base owner key every rail borrows, so it is last.
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

    /// The Peer client borrows the account's HTTP client and submitter and owns nothing of its own,
    /// so a refused build needs no release beyond being dropped.
    private func adopt(_ built: ApplePeerCashOutClient, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        peer = built
        return true
    }

    private func baseAccount() async throws -> AppleBaseAccount {
        let identity = try walletScope()
        // Cross the wallet/network boundary before deriving anything new. This zeroizes the old
        // Base key and cancels bridge work even if the new setup then fails.
        if identity != walletIdentity { await invalidate() }
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
