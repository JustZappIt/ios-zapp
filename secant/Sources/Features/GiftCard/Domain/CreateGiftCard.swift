// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// Why a card could not be minted. Each case is a distinct thing to tell the sender.
enum GiftCardCreationError: Error, Equatable {
    case invalidAmount

    case messageTooLong

    /// Funding a card needs a spending key this device holds.
    case keystoneUnsupported

    /// Gift cards exist on mainnet and testnet only.
    case unsupportedNetwork

    /// No chain tip yet, so there is no honest birthday to stamp on the card.
    case chainTipUnavailable

    /// The record did not read back as written. Refuse to fund what we cannot recover.
    case persistFailed
}

/// Mints a gift card and persists it, without touching the network.
///
/// The resulting card is a draft: key material exists and is on disk, nothing has been funded.
/// Funding is a separate step *precisely because* of the ordering — the record has to be durable
/// before any money moves, since a crash between submitting the funding transaction and writing
/// the record loses the ephemeral seed, and with it the funds, permanently. There is no reclaim.
struct CreateGiftCard {
    @Dependency(\.date) var date
    @Dependency(\.giftCardStorage) var giftCardStorage
    @Dependency(\.giftKey) var giftKey
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.uuid) var uuid
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    func callAsFunction(
        amount: Zatoshi,
        message: String? = nil,
        expiresAt: Date? = nil,
        sourceAccount: WalletAccount? = nil
    ) async throws -> StoredGiftCard {
        try ensure(amount.amount > 0, .invalidAmount)

        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmed?.isEmpty == true) ? nil : trimmed
        if let note {
            try ensure(GiftMessage.isWithinLimits(note), .messageTooLong)
        }

        // Keystone holds the spending key on the device, so funding one is a different flow. Out
        // of scope for v1, and better refused here than half-way through a funding proposal.
        // Funding resolves the selected account once and passes it here. Reading selection again
        // would let a concurrent account switch persist B as the owner while proposing the send
        // from A, after which reconciliation would search the wrong wallet.
        @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount?
        guard let account = sourceAccount ?? selectedWalletAccount else {
            throw GiftCardCreationError.chainTipUnavailable
        }
        try ensure(account.vendor != .keystone, .keystoneUnsupported)

        let networkType = zcashSDKEnvironment.network().networkType
        guard let networkName = GiftLinkCodec.networkName(networkType) else {
            throw GiftCardCreationError.unsupportedNetwork
        }

        // The chain tip, not the fully scanned height: this is where the recipient's scan begins,
        // and a birthday above the funding height would mean the note is never trial-decrypted.
        let tip = sdkSynchronizer.latestState().latestBlockHeight
        try ensure(tip > 0, .chainTipUnavailable)

        let keys = try giftKey.mint(networkType)
        let now = GiftLinkCodec.instantString(from: date.now())
        let card = try StoredGiftCard(
            id: uuid().uuidString,
            network: networkName,
            address: keys.address,
            mnemonic: keys.mnemonic,
            amountZatoshi: amount.amount,
            birthdayHeight: Int64(tip),
            sourceAccountUuid: account.id.giftStorageKey,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            expiresAt: expiresAt.map { GiftLinkCodec.instantString(from: $0) },
            message: note
        )

        try await giftCardStorage.add(card)

        // Read back before returning. The caller's next step is to move money to an address only
        // this record can spend from, so "the write appeared to succeed" is not good enough.
        try ensure(try await giftCardStorage.get(card.id) == card, .persistFailed)

        return card
    }

    private func ensure(_ condition: Bool, _ error: GiftCardCreationError) throws {
        if !condition { throw error }
    }
}

extension AccountUUID {
    /// The stable string a card records its funding account under.
    var giftStorageKey: String {
        id.map { String(format: "%02x", $0) }.joined()
    }
}
