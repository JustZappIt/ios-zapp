// SPDX-License-Identifier: MIT OR Apache-2.0
//
//  OfframpWalletKey.swift
//  Zapp
//
//  The owner key of the P2P cash-out account, exposed for the chat profile's reveal
//  surface. Mirrors Android's `ExportP2pWalletKeyUseCase`: same derivation
//  (`EvmKeyDerivation.derive(mnemonic:accountIndex:)` at index 0, the m/44'/60'/0'/0/0
//  path the offramp client already uses), same two fields, same zeroing of the exported
//  copy afterwards.
//
//  This is NOT the messaging identity's Ed25519 key — that one is derived by the chat
//  core from the same wallet seed and is never exported to app code. It is the secp256k1
//  key that controls the Base account P2P payouts land in.
//

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

/// A revealed P2P wallet key. The private half only ever exists inside a `RedactableString`,
/// which is `Undescribable` outside DEBUG — so it cannot surface through `dump`, a synthesized
/// `description`, or anything a crash reporter serialises.
struct OfframpWalletKey: Equatable, Sendable {
    let address: String
    let privateKeyHex: RedactableString
}

extension OfframpWalletKey {
    /// Derived on demand and never cached: the app holds the secret only for as long as the
    /// dialog showing it is on screen.
    static func derive() throws -> OfframpWalletKey {
        @Dependency(\.walletStorage) var walletStorage

        let mnemonic = try walletStorage.exportWallet().seedPhrase.value()
        let key = EvmKeyDerivation.shared.derive(mnemonic: mnemonic, accountIndex: 0, passphrase: "")
        let bytes = key.exportPrivateKeyBytes()

        defer {
            // `exportPrivateKeyBytes()` hands back a copy; Android wipes it the same way in the
            // `finally` of its use case. `zeroize()` then clears the key object's own buffer.
            for index in 0..<bytes.size {
                bytes.set(index: index, value: 0)
            }
            key.zeroize()
        }

        return OfframpWalletKey(
            address: key.address.checksumHex,
            privateKeyHex: RedactableString("0x\(bytes.toHex())")
        )
    }
}
