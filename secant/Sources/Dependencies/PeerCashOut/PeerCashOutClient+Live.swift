// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

extension PeerCashOutClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        Self(
            isConfigured: { Self.isConfigured() },
            capabilities: {
                // Known product, configuration and account absence is availability. Storage and
                // network failures are not: callers must preserve their last-known financial rows
                // instead of translating an outage into a successful empty history.
                guard Self.isConfigured() else { return .unavailable }
                return PeerCapabilities(try await OfframpSession.shared.peerClient().capabilities())
            },
            spendableBalance: {
                try await OfframpSession.shared.peerSpendableBalance()
            },
            normalizeHandle: { destination, raw in
                PeerHandleCheck(
                    try await OfframpSession.shared.peerClient().normalizeHandle(platformCode: destination, raw: raw)
                )
            },
            storedHandle: { destination in
                try await OfframpSession.shared.peerClient().storedHandle(platformCode: destination)
            },
            rate: { currency in
                try await OfframpSession.shared.peerClient().rate(currencyCode: currency).flatMap(PeerRate.init)
            },
            market: { destination, currency, amount in
                try await OfframpSession.shared.peerClient().market(
                    platformCode: destination,
                    currencyCode: currency,
                    amountMicros: amount?.microsString
                ).map(PeerMarketReading.init)
            },
            activeOrders: {
                try await OfframpSession.shared.peerClient().activeOrders().map(PeerOrder.init)
            },
            orderHistory: {
                try await OfframpSession.shared.peerClient().allOrders().map(PeerOrder.init)
            },
            order: { depositID in
                try await OfframpSession.shared.peerClient().order(depositIdComposite: depositID).map(PeerOrder.init)
            },
            observeOrder: { depositID in
                try await OfframpSession.shared.peerClient()
                    .observeOrder(depositIdComposite: depositID)
                    .peerProgressStream()
            },
            startCashOut: { draft in
                let generation = try await OfframpSession.shared.generationToken()
                // Both recovery books must be readable before authentication or admission. The
                // eventual claim below is atomic with Scan & Pay and refunds, not a UI-only check.
                try await OfframpSession.shared.prepareBaseReservations()
                let capabilities = PeerCapabilities(try await OfframpSession.shared.peerClient().capabilities())
                guard capabilities.isAvailable else { throw PeerCashOutClientError.unavailable }
                // Approve and create-deposit are one operation the user explicitly confirmed, so
                // they share this single authentication rather than prompting twice mid-flight.
                try await authenticate()
                return try await OfframpSession.shared.startPeerCashOut(
                    draft: draft,
                    attemptIDByteCount: capabilities.attemptIDByteCount,
                    expectedGeneration: generation
                )
            },
            recoverCashOut: { attemptID in
                let generation = try await OfframpSession.shared.generationToken()
                try await OfframpSession.shared.recoverPeerCashOut(
                    attemptID: attemptID,
                    expectedGeneration: generation
                )
            },
            retryCashOut: { attemptID in
                let generation = try await OfframpSession.shared.generationToken()
                try await authenticate()
                try await OfframpSession.shared.retryPeerCashOut(
                    attemptID: attemptID,
                    expectedGeneration: generation
                )
            },
            withdraw: { depositID, amount in
                let generation = try await OfframpSession.shared.generationToken()
                try await authenticate()
                try await OfframpSession.shared.withdrawPeerCashOut(
                    depositID: depositID,
                    amount: amount,
                    expectedGeneration: generation
                )
            },
            setAcceptingIntents: { depositID, accepting in
                let generation = try await OfframpSession.shared.generationToken()
                try await authenticate()
                try await OfframpSession.shared.setPeerAcceptingIntents(
                    depositID: depositID,
                    accepting: accepting,
                    expectedGeneration: generation
                )
            },
            clearOrderAction: { depositID in
                await OfframpSession.shared.peerRunner.clearOrderAction(depositID: depositID)
            },
            runnerState: {
                // Resolving the client first is what starts recovery: the runner is bound to it, and
                // a screen that only observed would show an empty list until something else asked.
                _ = try await OfframpSession.shared.peerClient()
                return await OfframpSession.shared.peerRunner.observe()
            },
            transactionURL: { hash in
                URL(string: try await OfframpSession.shared.peerClient().transactionUrl(txHash: hash))
            }
        )
    }

    /// Everything that decides whether the Peer rails exist at all, and nothing that can fail.
    ///
    /// The rails are pinned to Base mainnet by local config, and they sign from a Base account only
    /// a software wallet can derive — so the whole answer is on the device. Building the client to
    /// ask it would turn an outage into a "not available", which is what callers must never see.
    static func isConfigured() -> Bool {
        @Dependency(\.zcashSDKEnvironment) var environment
        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?

        guard selectedAccount?.vendor == .zcash else { return false }
        guard let pimlicoKey = PartnerKeys.p2pPimlicoApiKey, !pimlicoKey.isEmpty else { return false }
        return environment.network().networkType != .testnet
    }

    private static func authenticate() async throws {
        @Dependency(\.localAuthentication) var localAuthentication
        guard await localAuthentication.authenticate() else {
            throw PeerCashOutClientError.authenticationCancelled
        }
    }
}

extension OfframpSession {
    /// What the user may actually commit right now.
    ///
    /// Two sources, and both are needed. The runner knows about attempts too young to have written
    /// a checkpoint; the checkpoint book knows about attempts from a process that has since died.
    /// Counting only one of them lets two orders spend the same coins — and counting an attempt
    /// twice hides funds the user still has.
    func peerSpendableBalance() async throws -> PeerSpendableBalance {
        let client = try await peerClient()
        let startedIn = try generationToken()
        try await prepareBaseReservations()
        guard let balance = PeerAccount(try await client.account()).balance else { return .unavailable }
        try validateGeneration(startedIn)
        return await baseUSDCReservations.spendable(rawBalance: balance)
    }
}

private extension SkieSwiftFlow where T == ApplePeerStatus {
    func peerProgressStream() -> AsyncStream<PeerProgress> {
        AsyncStream { continuation in
            let task = Task {
                for await status in self {
                    guard !Task.isCancelled else { break }
                    continuation.yield(PeerProgress(status))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
