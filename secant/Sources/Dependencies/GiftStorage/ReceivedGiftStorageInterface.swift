// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension DependencyValues {
    var receivedGiftStorage: ReceivedGiftStorageClient {
        get { self[ReceivedGiftStorageClient.self] }
        set { self[ReceivedGiftStorageClient.self] = newValue }
    }
}

/// Receipts for gifts this wallet is collecting. Until a claim is final its receipt holds the
/// bearer link — the only way back to money already in flight — so the store is strict and a
/// corrupt blob throws rather than reading as empty.
@DependencyClient
struct ReceivedGiftStorageClient {
    var getAll: @Sendable () async throws -> [ReceivedGift]
    var record: @Sendable (ReceivedGift) async throws -> Void
    /// Only claim confirmation should call this, and only on evidence: a receipt settled early is
    /// a gift that cannot be retried if its claim never mines.
    var settle: @Sendable (_ address: String) async throws -> Void
    var markFinalized: @Sendable (_ address: String) async throws -> Void
    var markClaimedElsewhere: @Sendable (_ address: String) async throws -> Void
    /// Skips the write entirely when nothing changed, because it runs on every inconclusive look.
    var discardUnstarted: @Sendable (_ address: String) async throws -> Void
    /// True when any receipt still holds custody-critical retry material. Scoped to receipts that
    /// actually started a claim: a receipt is written before the scan, so "unsettled" alone would
    /// also cover every card this wallet only read — and blocking a wallet reset on one of those
    /// is a guard nothing can clear.
    var hasUnsettledClaims: @Sendable () async throws -> Bool
}

extension ReceivedGiftStorageClient: DependencyKey {
    static let liveValue: ReceivedGiftStorageClient = .live(walletStorage: .liveValue)

    static func live(walletStorage: WalletStorageClient) -> Self {
        let store = GiftStoreActor<ReceivedGift>(
            read: { try walletStorage.exportReceivedGifts() },
            write: { try walletStorage.importReceivedGifts($0) }
        )
        return Self(
            getAll: { try await store.getAll() },
            record: { gift in try await store.mutate { $0.recording(gift) } },
            settle: { address in try await store.mutate { $0.settling(address) } },
            markFinalized: { address in try await store.mutate { $0.finalizing(address) } },
            markClaimedElsewhere: { address in try await store.mutate { $0.markingClaimedElsewhere(address) } },
            discardUnstarted: { address in try await store.mutateIfChanged { $0.discardingUnstarted(address) } },
            hasUnsettledClaims: { try await store.getAll().contains { $0.isUnsettledClaim } }
        )
    }
}
