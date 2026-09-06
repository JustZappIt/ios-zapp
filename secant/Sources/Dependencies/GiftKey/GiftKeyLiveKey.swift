// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
@preconcurrency import MnemonicSwift
@preconcurrency import ZcashLightClientKit

extension GiftKeyClient: DependencyKey {
    static let liveValue = GiftKeyClient.live()

    /// There is no seed→address one-shot on iOS, so the route is
    /// seed → spending key (ZIP-32 account 0) → UFVK → unified address. It lands on the same
    /// all-available-keys UA as Android's seed-direct derivation — the load-bearing parity of
    /// `gift-cards.md` §2, pinned by the cross-platform vector fixtures.
    static func live() -> Self {
        Self(
            mint: { network in
                let phrase = try Mnemonic.generateMnemonic(strength: 256)
                return EphemeralGiftKeys(
                    mnemonic: phrase,
                    address: try address(for: phrase, network: network)
                )
            },
            deriveAddress: { mnemonic, network in
                try address(for: mnemonic, network: network)
            },
            deriveSeed: { mnemonic in
                [UInt8](try Mnemonic.deterministicSeedBytes(from: mnemonic))
            },
            deriveSpendingKey: { mnemonic, network in
                var seed = [UInt8](try Mnemonic.deterministicSeedBytes(from: mnemonic))
                defer {
                    for index in seed.indices { seed[index] = 0 }
                }
                return try DerivationTool(networkType: network)
                    .deriveUnifiedSpendingKey(seed: seed, accountIndex: Zip32AccountIndex(0))
            }
        )
    }

    private static func address(for mnemonic: String, network: NetworkType) throws -> String {
        var seed = [UInt8](try Mnemonic.deterministicSeedBytes(from: mnemonic))
        defer {
            for index in seed.indices { seed[index] = 0 }
        }
        let tool = DerivationTool(networkType: network)
        let spendingKey = try tool.deriveUnifiedSpendingKey(seed: seed, accountIndex: Zip32AccountIndex(0))
        let viewingKey = try tool.deriveUnifiedFullViewingKey(from: spendingKey)
        return try tool.deriveUnifiedAddressFrom(ufvk: viewingKey.stringEncoded).stringEncoded
    }
}
