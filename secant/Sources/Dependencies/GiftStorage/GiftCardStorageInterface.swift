// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension DependencyValues {
    var giftCardStorage: GiftCardStorageClient {
        get { self[GiftCardStorageClient.self] }
        set { self[GiftCardStorageClient.self] = newValue }
    }
}

/// The local half of every gift card this wallet has minted.
///
/// Custody-critical: for a card whose link has not been shared, this store is the only route back
/// to the funds. One closure per legal ledger transition; collapsing them into a generic mutator
/// is what the per-transition guards exist to prevent. A corrupt blob throws `GiftStoreCorrupt`
/// out of every reader — never an empty list.
@DependencyClient
struct GiftCardStorageClient {
    var getAll: @Sendable () async throws -> [StoredGiftCard]
    var get: @Sendable (_ id: String) async throws -> StoredGiftCard?
    /// Persists a freshly minted card. Must complete before its funding transaction is submitted.
    var add: @Sendable (StoredGiftCard) async throws -> Void
    /// Flags funding before SDK transaction creation. Submitted/funded transitions clear it.
    var setFundingAttemptedAt: @Sendable (_ id: String, _ at: String) async throws -> Void
    /// Stores the txid created after the durable funding-start marker.
    var recordFundingCreated: @Sendable (_ id: String, _ fundingTxid: String, _ at: String) async throws -> Void
    /// Records a submitted funding txid. The card stays a draft until the transaction mines.
    var recordFundingSubmitted: @Sendable (_ id: String, _ fundingTxid: String, _ at: String) async throws -> Void
    /// Clears a start marker only after a fully-synced wallet proves creation never happened.
    var markFundingNotCreated: @Sendable (_ id: String, _ at: String) async throws -> Void
    /// Archives terminal transaction ids and makes the same card safe to fund again.
    var markFundingExpired: @Sendable (_ id: String, _ fundingTxids: Set<String>, _ at: String) async throws -> Void
    /// Replaces expired candidates with the single still-live transaction in one atomic write.
    var replaceExpiredFunding: @Sendable (
        _ id: String,
        _ expiredFundingTxids: Set<String>,
        _ activeFundingTxid: String,
        _ at: String
    ) async throws -> Void
    var markFunded: @Sendable (_ id: String, _ fundingTxid: String, _ at: String) async throws -> Void
    var markShared: @Sendable (_ id: String, _ at: String) async throws -> Void
    /// Records that the card's own wallet was scanned and still held its funds.
    var recordChecked: @Sendable (_ id: String, _ at: String) async throws -> Void
    /// Records that the card's funding and a finalized claim spend were observed.
    var markClaimed: @Sendable (_ id: String, _ at: String) async throws -> Void
    /// True while `accountUuid` — or any account, when nil — owns funded cards whose links were
    /// never shared. Blocks deleting that account, and blocks the wallet wipe, which clears this
    /// whole store.
    var hasUnsharedFunds: @Sendable (_ accountUuid: String?) async throws -> Bool
    /// Emits the current list on subscribe and after every mutation.
    var observe: @Sendable () -> AsyncStream<[StoredGiftCard]> = { .finished }
}

extension GiftCardStorageClient: DependencyKey {
    static let liveValue: GiftCardStorageClient = .live(walletStorage: .liveValue)

    static func live(walletStorage: WalletStorageClient) -> Self {
        let store = GiftStoreActor<StoredGiftCard>(
            read: { try walletStorage.exportGiftCards() },
            write: { try walletStorage.importGiftCards($0) }
        )
        return Self(
            getAll: { try await store.getAll() },
            get: { id in try await store.getAll().first { $0.id == id } },
            add: { card in try await store.mutate { try GiftCardLedger.add($0, card: card) } },
            setFundingAttemptedAt: { id, at in
                try await store.mutate { try GiftCardLedger.setFundingAttemptedAt($0, id: id, at: at) }
            },
            recordFundingCreated: { id, txid, at in
                try await store.mutate { try GiftCardLedger.recordFundingCreated($0, id: id, fundingTxid: txid, at: at) }
            },
            recordFundingSubmitted: { id, txid, at in
                try await store.mutate { try GiftCardLedger.recordFundingSubmitted($0, id: id, fundingTxid: txid, at: at) }
            },
            markFundingNotCreated: { id, at in
                try await store.mutate { try GiftCardLedger.markFundingNotCreated($0, id: id, at: at) }
            },
            markFundingExpired: { id, txids, at in
                try await store.mutate { try GiftCardLedger.markFundingExpired($0, id: id, fundingTxids: txids, at: at) }
            },
            replaceExpiredFunding: { id, expired, active, at in
                try await store.mutate {
                    try GiftCardLedger.replaceExpiredFunding(
                        $0,
                        id: id,
                        expiredFundingTxids: expired,
                        activeFundingTxid: active,
                        at: at
                    )
                }
            },
            markFunded: { id, txid, at in
                try await store.mutate { try GiftCardLedger.markFunded($0, id: id, fundingTxid: txid, at: at) }
            },
            markShared: { id, at in
                try await store.mutate { try GiftCardLedger.markShared($0, id: id, at: at) }
            },
            recordChecked: { id, at in
                try await store.mutate { try GiftCardLedger.recordChecked($0, id: id, at: at) }
            },
            markClaimed: { id, at in
                try await store.mutate { try GiftCardLedger.markClaimed($0, id: id, at: at) }
            },
            hasUnsharedFunds: { accountUuid in
                GiftCardLedger.hasUnsharedFunds(try await store.getAll(), accountUuid: accountUuid)
            },
            observe: { store.stream() }
        )
    }
}

/// One actor per store serializing every read-modify-write: every mutation rewrites the whole
/// blob, so concurrent mutations would interleave and lose a card.
actor GiftStoreActor<Record: Sendable> {
    private let read: @Sendable () throws -> [Record]
    private let write: @Sendable ([Record]) throws -> Void
    private var continuations: [UUID: AsyncStream<[Record]>.Continuation] = [:]

    init(
        read: @escaping @Sendable () throws -> [Record],
        write: @escaping @Sendable ([Record]) throws -> Void
    ) {
        self.read = read
        self.write = write
    }

    func getAll() throws -> [Record] {
        try read()
    }

    /// A corrupt read refuses the write — that is what makes failing closed safe.
    func mutate(_ transform: ([Record]) throws -> [Record]) throws {
        let next = try transform(try read())
        try write(next)
        for continuation in continuations.values {
            continuation.yield(next)
        }
    }

    /// Skips the write (and the emissions) when the transform changes nothing.
    func mutateIfChanged(_ transform: ([Record]) throws -> [Record]) throws where Record: Equatable {
        let current = try read()
        let next = try transform(current)
        guard next != current else { return }
        try write(next)
        for continuation in continuations.values {
            continuation.yield(next)
        }
    }

    nonisolated func stream() -> AsyncStream<[Record]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.subscribe(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unsubscribe(id: id) }
            }
        }
    }

    private func subscribe(id: UUID, continuation: AsyncStream<[Record]>.Continuation) {
        continuations[id] = continuation
        // Seed with the current list; a corrupt store seeds nothing and readers surface the error
        // through getAll instead.
        if let current = try? read() {
            continuation.yield(current)
        }
    }

    private func unsubscribe(id: UUID) {
        continuations[id] = nil
    }
}
