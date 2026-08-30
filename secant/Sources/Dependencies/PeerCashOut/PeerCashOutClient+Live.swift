// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

extension PeerCashOutClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        Self(
            capabilities: {
                // A build without the rails must still answer rather than throw: the settings
                // screen lists Peer destinations as unavailable instead of hiding that they exist.
                guard let client = try? await OfframpSession.shared.peerClient() else {
                    return .unavailable
                }
                return PeerCapabilities(client.capabilities())
            },
            account: {
                PeerAccount(try await OfframpSession.shared.peerClient().account())
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
                let capabilities = PeerCapabilities(try await OfframpSession.shared.peerClient().capabilities())
                guard capabilities.isAvailable else { throw PeerCashOutClientError.unavailable }
                // Approve and create-deposit are one operation the user explicitly confirmed, so
                // they share this single authentication rather than prompting twice mid-flight.
                try await authenticate()
                let runner = OfframpSession.shared.peerRunner
                let id = await runner.newAttemptID(byteCount: capabilities.attemptIDByteCount)
                guard let started = await runner.start(id: id, draft: draft) else {
                    throw PeerCashOutClientError.unavailable
                }
                return started
            },
            recoverCashOut: { attemptID in
                _ = try await OfframpSession.shared.peerClient()
                await OfframpSession.shared.peerRunner.recover(id: attemptID)
            },
            retryCashOut: { attemptID in
                _ = try await OfframpSession.shared.peerClient()
                try await authenticate()
                await OfframpSession.shared.peerRunner.retry(id: attemptID)
            },
            withdraw: { depositID, amount in
                _ = try await OfframpSession.shared.peerClient()
                try await authenticate()
                await OfframpSession.shared.peerRunner.withdraw(depositID: depositID, amount: amount)
            },
            setAcceptingIntents: { depositID, accepting in
                _ = try await OfframpSession.shared.peerClient()
                try await authenticate()
                await OfframpSession.shared.peerRunner
                    .setAcceptingIntents(depositID: depositID, accepting: accepting)
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
            reconcile: {
                _ = try await OfframpSession.shared.peerClient()
                await OfframpSession.shared.peerRunner.reconcile()
            },
            transactionURL: { hash in
                URL(string: try await OfframpSession.shared.peerClient().transactionUrl(txHash: hash))
            }
        )
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
        guard let balance = PeerAccount(try await client.account()).balance else { return .unavailable }
        let runs = await peerRunner.currentState.runs
        let liveIDs = Set(runs.map(\.id))
        let dormant = try await client.attempts()
            .filter { $0.holdsUnescrowedFunds && !liveIDs.contains($0.id) }
            .map { PeerAttempt($0).amount }
        return .ready(
            balance: balance,
            committed: UsdcAmount.sum(runs.filter(\.holdsFunds).map(\.amount)) + UsdcAmount.sum(dormant)
        )
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
