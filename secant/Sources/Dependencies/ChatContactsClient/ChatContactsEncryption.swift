//
//  ChatContactsEncryption.swift
//  Zapp
//
//  Serialization + encryption for the chat-contacts file.
//
//  Reuses the address book's key material and envelope
//  (`Int64BE(version) || salt(32) || ChaChaPoly.seal(...)`), but its own file,
//  its own payload, and — deliberately — its own version policy.
//

import ComposableArchitecture
import CryptoKit
import Foundation
import ZcashLightClientKit

extension ChatContactsClient {
    enum ChatContactsClientError: Error, Equatable {
        case missingEncryptionKey
        case fileIdentifier
        case documentsDirectory
        case corruptedData
        /// A file written by a NEWER build. See `contactsFrom(encryptedData:)`.
        case unknownVersion(Int)
    }

    enum Constants {
        static let int64Size = MemoryLayout<Int64>.size
    }

    // MARK: - Encrypt

    static func encrypt(_ contacts: ChatContacts, account: Account) throws -> Data {
        @Dependency(\.walletStorage) var walletStorage

        guard let encryptionKeys = try? walletStorage.exportAddressBookEncryptionKeys(),
              let key = encryptionKeys.getCached(account: account) else {
            throw ChatContactsClientError.missingEncryptionKey
        }

        var encryptionVersionData = Data()
        encryptionVersionData.append(contentsOf: intToBytes(AddressBookEncryptionKeys.Constants.version))

        let plaintext = serialize(contacts)

        let salt = SymmetricKey(size: SymmetricKeySize.bits256)

        return try salt.withUnsafeBytes { salt in
            let salt = Data(salt)
            let subKey = key.deriveEncryptionKey(salt: salt)
            let sealed = try ChaChaPoly.seal(plaintext, using: subKey)

            return encryptionVersionData + salt + sealed.combined
        }
    }

    // MARK: - Decrypt

    static func contactsFrom(encryptedData: Data, account: Account) throws -> ChatContacts {
        @Dependency(\.walletStorage) var walletStorage

        guard let encryptionKeys = try? walletStorage.exportAddressBookEncryptionKeys(),
              let key = encryptionKeys.getCached(account: account) else {
            throw ChatContactsClientError.missingEncryptionKey
        }

        var offset = 0

        let versionBytes = try subdata(of: encryptedData, in: offset..<(offset + Constants.int64Size))
        offset += Constants.int64Size

        guard let envelopeVersion = bytesToInt(Array(versionBytes)),
              envelopeVersion == AddressBookEncryptionKeys.Constants.version else {
            throw ChatContactsClientError.corruptedData
        }

        let salt = try subdata(of: encryptedData, in: offset..<(offset + 32))
        offset += 32

        let subKey = key.deriveEncryptionKey(salt: salt)
        let sealed = try ChaChaPoly.SealedBox(combined: encryptedData.subdata(in: offset..<encryptedData.count))
        let plaintext = try ChaChaPoly.open(sealed, using: subKey)

        return try deserialize(plaintext)
    }

    // MARK: - Payload

    static func serialize(_ contacts: ChatContacts) -> Data {
        var data = Data()

        data.append(contentsOf: intToBytes(ChatContacts.Constants.version))
        data.append(contentsOf: serializeDate(contacts.lastUpdated))
        data.append(contentsOf: intToBytes(contacts.contacts.count))

        contacts.contacts.forEach { contact in
            data.append(contentsOf: serializeDate(contact.lastUpdated))
            data.append(contentsOf: serializeString(contact.publicKey))
            data.append(contentsOf: serializeString(contact.name))
            data.append(contentsOf: serializeString(contact.address))

            data.append(contentsOf: intToBytes(contact.walletAddresses.count))
            contact.walletAddresses.sorted { $0.key < $1.key }.forEach { key, value in
                data.append(contentsOf: serializeString(key))
                data.append(contentsOf: serializeString(value))
            }

            data.append(contentsOf: intToBytes(contact.isBlocked ? 1 : 0))
            data.append(contentsOf: intToBytes(contact.isSaved ? 1 : 0))
        }

        return data
    }

    static func deserialize(_ data: Data) throws -> ChatContacts {
        var offset = 0

        let version = try readInt(from: data, at: &offset)

        // THROW, never `return .empty`.
        //
        // The address book returns an empty book for an unrecognised version, caches
        // it, and writes it back on the next save — so an older build silently
        // destroys a newer file. Throwing means a downgraded build surfaces an error
        // and REFUSES to write, instead of quietly deleting the user's contacts.
        // This is the one line that makes every future version safe.
        guard version <= ChatContacts.Constants.version else {
            throw ChatContactsClientError.unknownVersion(version)
        }

        let lastUpdated = try readDate(from: data, at: &offset)
        let count = try readInt(from: data, at: &offset)

        var contacts: IdentifiedArrayOf<ChatContact> = []

        for _ in 0..<count {
            let contactLastUpdated = try readDate(from: data, at: &offset)
            let publicKey = try readString(from: data, at: &offset)
            let name = try readString(from: data, at: &offset)
            let address = try readString(from: data, at: &offset)

            let walletAddressCount = try readInt(from: data, at: &offset)
            var walletAddresses: [String: String] = [:]
            for _ in 0..<walletAddressCount {
                let key = try readString(from: data, at: &offset)
                let value = try readString(from: data, at: &offset)
                walletAddresses[key] = value
            }

            let isBlocked = try readInt(from: data, at: &offset) == 1
            let isSaved = try readInt(from: data, at: &offset) == 1

            // A record with no public key is meaningless; skip it. We have still
            // consumed its full length, so the offset stays in sync — unlike the
            // address book, whose reader aborts mid-record on an empty field and
            // corrupts every contact after it.
            guard !publicKey.isEmpty else { continue }

            contacts.updateOrAppend(
                ChatContact(
                    publicKey: publicKey,
                    name: name,
                    lastUpdated: contactLastUpdated,
                    address: address,
                    walletAddresses: walletAddresses,
                    isBlocked: isBlocked,
                    isSaved: isSaved
                )
            )
        }

        return ChatContacts(lastUpdated: lastUpdated, version: version, contacts: contacts)
    }

    // MARK: - Primitives
    //
    // Big-endian, every integer widened to 8 bytes; a string is `len(8B) || utf8`.
    // Same shape as the address book's, so the two files read alike — but these
    // readers never abort mid-record.

    static func intToBytes(_ value: Int) -> [UInt8] {
        withUnsafeBytes(of: Int64(value).bigEndian) { Array($0) }
    }

    static func bytesToInt(_ bytes: [UInt8]) -> Int? {
        guard bytes.count == Constants.int64Size else { return nil }

        return Int(bytes.withUnsafeBytes { $0.load(as: Int64.self).bigEndian })
    }

    static func serializeString(_ value: String) -> [UInt8] {
        let bytes = Array(value.utf8)

        return intToBytes(bytes.count) + bytes
    }

    static func serializeDate(_ date: Date) -> [UInt8] {
        intToBytes(Int(date.timeIntervalSince1970))
    }

    static func subdata(of data: Data, in range: Range<Data.Index>) throws -> Data {
        guard range.lowerBound >= 0, data.count >= range.upperBound else {
            throw ChatContactsClientError.corruptedData
        }

        return data.subdata(in: range)
    }

    static func readInt(from data: Data, at offset: inout Int) throws -> Int {
        let bytes = try subdata(of: data, in: offset..<(offset + Constants.int64Size))
        offset += Constants.int64Size

        guard let value = bytesToInt(Array(bytes)) else {
            throw ChatContactsClientError.corruptedData
        }

        return value
    }

    /// Reads the length, then that many bytes. An empty string is a legitimate
    /// value (a chat-only contact has no ZEC address) and must NOT abort the read.
    static func readString(from data: Data, at offset: inout Int) throws -> String {
        let length = try readInt(from: data, at: &offset)

        guard length >= 0 else { throw ChatContactsClientError.corruptedData }
        guard length > 0 else { return "" }

        let bytes = try subdata(of: data, in: offset..<(offset + length))
        offset += length

        guard let value = String(data: bytes, encoding: .utf8) else {
            throw ChatContactsClientError.corruptedData
        }

        return value
    }

    static func readDate(from data: Data, at offset: inout Int) throws -> Date {
        Date(timeIntervalSince1970: TimeInterval(try readInt(from: data, at: &offset)))
    }
}
