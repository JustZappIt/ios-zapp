// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

/// The persisted record has to be able to become a claimable link, every time.
///
/// This is the invariant the create flow leans on: it encodes the link *before* funding precisely
/// so a record that cannot produce one is caught while the money is still in the sender's wallet.
/// If these break, a funded card is unreachable and there is no reclaim.
@Suite struct StoredGiftCardLinkTests {
    /// BIP-39 test vector for all-zero entropy. Never a real wallet.
    private static let mnemonic =
        "\(String(repeating: "abandon ", count: 23))art"

    private static let address = "u1exampleunifiedaddressforgiftcardtests"
    private static let amount: Int64 = 100_000_000
    private static let birthday: Int64 = 2_800_000

    @Test func aStoredCardRoundTripsThroughALink() throws {
        let decoded = try GiftLinkCodec.decode(try GiftLinkCodec.encode(card().toLinkPayload()), walletNetwork: .mainnet)

        #expect(decoded.mnemonic == Self.mnemonic)
        #expect(decoded.amountZatoshi == String(Self.amount))
        #expect(decoded.birthdayHeight == Self.birthday)
        #expect(decoded.version == GiftLinkCodec.version)
    }

    @Test func carriesTheOptionalMessageAndExpiryThroughAndOmitsThemWhenAbsent() throws {
        let full = try card(message: "happy birthday", expiresAt: "2026-12-24T00:00:00Z")
        let bare = try card(message: nil, expiresAt: nil)

        let decodedFull = try GiftLinkCodec.decode(try GiftLinkCodec.encode(full.toLinkPayload()), walletNetwork: .mainnet)
        let decodedBare = try GiftLinkCodec.decode(try GiftLinkCodec.encode(bare.toLinkPayload()), walletNetwork: .mainnet)

        #expect(decodedFull.message == "happy birthday")
        #expect(decodedFull.expiresAt == "2026-12-24T00:00:00Z")
        #expect(decodedBare.message == nil)
        #expect(decodedBare.expiresAt == nil)
    }

    @Test func aTestnetCardEncodesAsATestnetLink() throws {
        let link = try GiftLinkCodec.encode(card(network: "test").toLinkPayload())

        #expect(try GiftLinkCodec.decode(link, walletNetwork: .testnet).network == "test")
        // And a mainnet wallet must refuse it rather than scan for a note that cannot exist.
        #expect(throws: GiftLinkError.networkMismatch) {
            try GiftLinkCodec.decode(link, walletNetwork: .mainnet)
        }
    }

    @Test func theLinkStaysOutOfTheRecordsDescription() throws {
        // The record and the payload both hold the bearer phrase. Interpolating either into a log
        // line or a crash report would publish the money.
        let rendered = try card().description

        #expect(!rendered.contains(Self.mnemonic))
        #expect(!rendered.contains(Self.address))
        #expect(rendered.contains("redacted"))
    }

    private func card(
        network: String = "main",
        message: String? = nil,
        expiresAt: String? = nil
    ) throws -> StoredGiftCard {
        try StoredGiftCard(
            id: "6f1c0f6e-0b6b-4f2e-9a5a-6f1c0f6e0b6b",
            network: network,
            address: Self.address,
            mnemonic: Self.mnemonic,
            amountZatoshi: Self.amount,
            birthdayHeight: Self.birthday,
            sourceAccountUuid: "account-uuid",
            createdAt: "2026-08-20T12:00:00Z",
            updatedAt: "2026-08-20T12:00:00Z",
            status: .draft,
            expiresAt: expiresAt,
            message: message
        )
    }
}
