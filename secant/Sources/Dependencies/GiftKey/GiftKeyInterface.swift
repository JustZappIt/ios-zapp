// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension DependencyValues {
    var giftKey: GiftKeyClient {
        get { self[GiftKeyClient.self] }
        set { self[GiftKeyClient.self] = newValue }
    }
}

/// A throwaway wallet backing one gift card. The mnemonic is the money — never log this.
struct EphemeralGiftKeys: Equatable {
    let mnemonic: String
    let address: String
}

extension EphemeralGiftKeys: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "EphemeralGiftKeys(REDACTED)" }
    var debugDescription: String { description }
}

/// Mints and re-derives the throwaway wallets behind gift cards.
///
/// Split out from the use cases because it is the only part of the feature that needs the Rust
/// derivation backend: with it behind an interface, everything above can be exercised without it.
///
/// The key material is random, not derived from the wallet seed at a ZIP 32 path. That is a
/// deliberate v1 choice and the reason the keychain record is custody-critical: a restored backup
/// cannot regenerate these.
@DependencyClient
struct GiftKeyClient {
    /// Generates a fresh 24-word phrase and its unified address. Entirely offline.
    var mint: @Sendable (NetworkType) throws -> EphemeralGiftKeys
    /// Re-derives the unified address a phrase produces — the card's identity everywhere, since
    /// the link deliberately does not carry it.
    var deriveAddress: @Sendable (_ mnemonic: String, _ network: NetworkType) throws -> String
    /// The raw seed behind a phrase, for standing up the card's own isolated synchronizer.
    ///
    /// Returns a fresh array each call; the caller owns it and must zero it when done.
    var deriveSeed: @Sendable (_ mnemonic: String) throws -> [UInt8]
    /// The spending key for a card's throwaway wallet, which authorises moving its funds out.
    var deriveSpendingKey: @Sendable (_ mnemonic: String, _ network: NetworkType) throws -> UnifiedSpendingKey
}
