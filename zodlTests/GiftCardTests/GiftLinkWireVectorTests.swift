// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ZcashLightClientKit
@testable import zodl_internal

/// Frozen cross-platform wire vectors, written out rather than derived from any production
/// constant. A failure here means the format moved: fix the codec, never regenerate the literals.
@Suite struct GiftLinkWireVectorTests {
    private static let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"

    private static let bareLink = "https://gift.justzappit.xyz/c/v1#k=eyJhbW91bnRaYXRvc2hpIjoiMTAwMDAwMDAwMCIsImJpcnRoZGF5SGVpZ2h0IjoyODAwMDAwLCJjcmVhdGVkQXQiOiIyMDI2LTA4LTIwVDEyOjAwOjAwWiIsIm1uZW1vbmljIjoiYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFydCIsIm5ldHdvcmsiOiJtYWluIiwidiI6MX0"

    private static let fullLink = "https://gift.justzappit.xyz/c/v1#k=eyJhbW91bnRaYXRvc2hpIjoiMjUwMDAwIiwiYmlydGhkYXlIZWlnaHQiOjI5MDAwMDAsImNyZWF0ZWRBdCI6IjIwMjYtMDgtMjFUMDk6MzA6MDBaIiwiZXhwaXJlc0F0IjoiMjAyNi0xMi0yNFQwMDowMDowMFoiLCJtZXNzYWdlIjoiaGFwcHkgYmlydGhkYXkg8J-OgSIsIm1uZW1vbmljIjoiYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFiYW5kb24gYWJhbmRvbiBhYmFuZG9uIGFydCIsIm5ldHdvcmsiOiJtYWluIiwidiI6MX0"

    @Test func decodesTheFrozenLinkThatOmitsEveryOptional() throws {
        let payload = try GiftLinkCodec.decode(Self.bareLink, walletNetwork: .mainnet)

        #expect(payload.version == 1)
        #expect(payload.network == "main")
        #expect(payload.amountZatoshi == "1000000000")
        #expect(payload.mnemonic == Self.mnemonic)
        #expect(payload.birthdayHeight == 2_800_000)
        #expect(payload.createdAt == "2026-08-20T12:00:00Z")
        #expect(payload.expiresAt == nil)
        #expect(payload.message == nil)
    }

    @Test func decodesTheFrozenLinkCarryingAMessageAndAnExpiry() throws {
        let payload = try GiftLinkCodec.decode(Self.fullLink, walletNetwork: .mainnet)

        #expect(payload.version == 1)
        #expect(payload.network == "main")
        #expect(payload.amountZatoshi == "250000")
        #expect(payload.mnemonic == Self.mnemonic)
        #expect(payload.birthdayHeight == 2_900_000)
        #expect(payload.createdAt == "2026-08-21T09:30:00Z")
        #expect(payload.expiresAt == "2026-12-24T00:00:00Z")
        #expect(payload.message == "happy birthday 🎁")
    }

    @Test func encodesTheFrozenPayloadsBackToTheSameLinksByteForByte() throws {
        let bare = GiftLinkPayload(
            version: 1,
            network: "main",
            amountZatoshi: "1000000000",
            mnemonic: Self.mnemonic,
            birthdayHeight: 2_800_000,
            createdAt: "2026-08-20T12:00:00Z",
            expiresAt: nil,
            message: nil
        )
        let full = GiftLinkPayload(
            version: 1,
            network: "main",
            amountZatoshi: "250000",
            mnemonic: Self.mnemonic,
            birthdayHeight: 2_900_000,
            createdAt: "2026-08-21T09:30:00Z",
            expiresAt: "2026-12-24T00:00:00Z",
            message: "happy birthday 🎁"
        )

        #expect(try GiftLinkCodec.encode(bare) == Self.bareLink)
        #expect(try GiftLinkCodec.encode(full) == Self.fullLink)
    }
}
