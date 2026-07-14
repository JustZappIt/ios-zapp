//
//  ChatContactsLiveKey.swift
//  Zapp
//

import ComposableArchitecture
import Foundation
import ZcashLightClientKit

extension ChatContactsClient: DependencyKey {
    static let liveValue: ChatContactsClient = Self.live()

    static func live() -> Self {
        let impl = ChatContactsImpl()

        return ChatContactsClient(
            all: { try impl.all($0) },
            save: { try impl.save($0, $1) },
            delete: { try impl.delete($0, publicKey: $1) },
            setBlocked: { try impl.setBlocked($0, publicKey: $1, name: $2, isBlocked: $3) },
            resetAccount: { try impl.resetAccount($0) }
        )
    }
}

private final class ChatContactsImpl: @unchecked Sendable {
    func all(_ account: Account) throws -> ChatContacts {
        try load(account)
    }

    /// Preserves `isBlocked`: saving someone you have blocked must not unblock them.
    func save(_ account: Account, _ contact: ChatContact) throws -> ChatContacts {
        var contacts = try load(account)
        let key = PublicKeyRules.sanitize(contact.publicKey)

        var updated = contact
        updated.publicKey = key
        updated.isBlocked = contacts.byPublicKey[key]?.isBlocked ?? contact.isBlocked
        updated.isSaved = true
        updated.lastUpdated = Date()

        contacts.contacts.updateOrAppend(updated)

        return try store(account, contacts)
    }

    /// A blocked contact degrades to a block-only row rather than vanishing —
    /// otherwise "remove from contacts" would silently unblock them.
    func delete(_ account: Account, publicKey: String) throws -> ChatContacts {
        var contacts = try load(account)
        let key = PublicKeyRules.sanitize(publicKey)

        guard let existing = contacts.byPublicKey[key] else { return contacts }

        if existing.isBlocked {
            var blockOnly = existing
            blockOnly.isSaved = false
            blockOnly.name = ""
            blockOnly.address = ""
            blockOnly.walletAddresses = [:]
            blockOnly.lastUpdated = Date()
            contacts.contacts.updateOrAppend(blockOnly)
        } else {
            contacts.contacts.remove(id: key)
        }

        return try store(account, contacts)
    }

    /// Blocking a stranger mints a row for someone who was never a contact.
    /// Unblocking such a row removes it, rather than leaving a nameless ghost.
    func setBlocked(_ account: Account, publicKey: String, name: String, isBlocked: Bool) throws -> ChatContacts {
        var contacts = try load(account)
        let key = PublicKeyRules.sanitize(publicKey)

        if let existing = contacts.byPublicKey[key] {
            if !isBlocked && !existing.isSaved {
                contacts.contacts.remove(id: key)
            } else {
                var updated = existing
                updated.isBlocked = isBlocked
                updated.lastUpdated = Date()
                contacts.contacts.updateOrAppend(updated)
            }
        } else if isBlocked {
            contacts.contacts.updateOrAppend(
                ChatContact(publicKey: key, name: name, isBlocked: true, isSaved: false)
            )
        }

        return try store(account, contacts)
    }

    func resetAccount(_ account: Account) throws {
        let url = try fileURL(account)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Storage

    /// Local only. Deliberately not synced to iCloud: the address book's merge
    /// carries just `name` and `lastUpdated` (it already drops `chainId`), so it
    /// would quietly discard `isBlocked` — and a social graph is the last thing to
    /// put in someone's cloud by default.
    private func load(_ account: Account) throws -> ChatContacts {
        let url = try fileURL(account)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }

        let encrypted = try Data(contentsOf: url)

        return try ChatContactsClient.contactsFrom(encryptedData: encrypted, account: account)
    }

    private func store(_ account: Account, _ contacts: ChatContacts) throws -> ChatContacts {
        var updated = contacts
        updated.lastUpdated = Date()
        updated.version = ChatContacts.Constants.version

        let encrypted = try ChatContactsClient.encrypt(updated, account: account)
        try encrypted.write(to: try fileURL(account), options: .atomic)

        return updated
    }

    private func fileURL(_ account: Account) throws -> URL {
        @Dependency(\.walletStorage) var walletStorage

        guard let keys = try? walletStorage.exportAddressBookEncryptionKeys(),
              let key = keys.getCached(account: account) else {
            throw ChatContactsClient.ChatContactsClientError.missingEncryptionKey
        }

        guard let filename = key.chatContactsFileIdentifier() else {
            throw ChatContactsClient.ChatContactsClientError.fileIdentifier
        }

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ChatContactsClient.ChatContactsClientError.documentsDirectory
        }

        return documents.appendingPathComponent(filename)
    }
}
