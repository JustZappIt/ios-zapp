//
//  ChatContact.swift
//  Zapp
//
//  A chat contact is keyed by its Ed25519 public key, NOT by a ZEC address.
//
//  This is why it cannot live in the address book: `Contact.id` there is
//  "\(address)-\(chainId)", so identity is address-derived — and a chat contact
//  may have no ZEC address at all. (The address-book parser also aborts
//  mid-record on a zero-length address, which would corrupt every contact after
//  it, and its feature reducer routes any row with a `chainId` into the swap
//  picker.) The address book is upstream code we merge from monthly; it stays at
//  zero diff.
//

import ComposableArchitecture
import Foundation

struct ChatContact: Equatable, Codable, Identifiable, Hashable {
    /// Always normalised through `PublicKeyRules.sanitize` before it gets here.
    var id: String { publicKey }

    var publicKey: String
    var name: String
    var lastUpdated: Date

    /// Primary (unified) ZEC address. Empty for a chat-only or block-only row.
    var address: String

    /// Per-chain extras, keyed by `AddrType`.
    var walletAddresses: [String: String]

    var isBlocked: Bool

    /// False for a row that exists only because the user blocked a stranger.
    ///
    /// Android infers "saved vs block-only" from membership of the worklet's
    /// contact registry. We do not mirror into that registry (nothing reads it),
    /// so the distinction is explicit instead of inferred.
    var isSaved: Bool

    enum AddrType {
        static let transparent = "zcash_transparent"
        static let evm = "evm"
        static let solana = "solana"
    }

    init(
        publicKey: String,
        name: String,
        lastUpdated: Date = Date(),
        address: String = "",
        walletAddresses: [String: String] = [:],
        isBlocked: Bool = false,
        isSaved: Bool = true
    ) {
        self.publicKey = PublicKeyRules.sanitize(publicKey)
        self.name = name
        self.lastUpdated = lastUpdated
        self.address = address
        self.walletAddresses = walletAddresses
        self.isBlocked = isBlocked
        self.isSaved = isSaved
    }
}

struct ChatContacts: Equatable, Codable {
    enum Constants {
        static let version = 1
    }

    var lastUpdated: Date
    var version: Int
    var contacts: IdentifiedArrayOf<ChatContact>

    static let empty = ChatContacts(
        lastUpdated: .distantPast,
        version: Constants.version,
        contacts: []
    )
}

// MARK: - Lookups

extension ChatContacts {
    /// The core normalises conversation participant keys but stores contact keys
    /// verbatim, so an unnormalised key silently never matches. Every lookup and
    /// every comparison goes through `sanitize`.
    var byPublicKey: [String: ChatContact] {
        Dictionary(
            contacts.map { (PublicKeyRules.sanitize($0.publicKey), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var blockedKeys: Set<String> {
        Set(contacts.filter(\.isBlocked).map { PublicKeyRules.sanitize($0.publicKey) })
    }

    func isBlocked(_ publicKey: String?) -> Bool {
        guard let publicKey else { return false }

        return blockedKeys.contains(PublicKeyRules.sanitize(publicKey))
    }

    func contact(for publicKey: String?) -> ChatContact? {
        guard let publicKey else { return nil }

        return byPublicKey[PublicKeyRules.sanitize(publicKey)]
    }

    /// The rows a user should see in a contact list: block-only rows are not contacts.
    var saved: [ChatContact] {
        contacts.filter(\.isSaved).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
