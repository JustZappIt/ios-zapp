// SPDX-License-Identifier: MIT OR Apache-2.0

import CryptoKit
import Foundation
@preconcurrency import ZappOfframp
@preconcurrency import ZcashLightClientKit

private struct OfframpStoragePayload: Codable {
    static let version = 1

    var version = Self.version
    var relayPrivateKey: String?
    var relayPublicKey: String?
    var paymentAddresses: [String: String] = [:]
    var checkpointJSON: String?
    var topUpCheckpointJSON: String?
    var refundCheckpointJSON: String?
}

enum OfframpStorageError: Error {
    case missingEncryptionKey
    case documentsDirectory
    case invalidEnvelope
    case unsupportedVersion(Int)
}

/// Wallet-scoped encrypted storage. Unknown payload versions throw and are never overwritten.
final class OfframpEncryptedStorage: NSObject, AppleOfframpStorage, @unchecked Sendable {
    private let lock = NSLock()
    private let key: AddressBookKey
    private let fileURL: URL

    init(account: Account, walletStorage: WalletStorageClient) throws {
        let keys = try walletStorage.exportAddressBookEncryptionKeys()
        guard let key = keys.getCached(account: account),
              let filename = key.offrampFileIdentifier() else {
            throw OfframpStorageError.missingEncryptionKey
        }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw OfframpStorageError.documentsDirectory
        }
        self.key = key
        self.fileURL = documents.appendingPathComponent(filename)
    }

    func relayPrivateKey() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.relayPrivateKey })
    }

    func relayPublicKey() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.relayPublicKey })
    }

    func paymentAddress(orderId: String) throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.paymentAddresses[orderId] })
    }

    func checkpointJson() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.checkpointJSON })
    }

    func topUpCheckpointJson() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.topUpCheckpointJSON })
    }

    func refundCheckpointJson() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.refundCheckpointJSON })
    }

    func storeRelay(privateKeyHex: String, publicKeyHex: String) throws {
        try mutate { payload in
            payload.relayPrivateKey = privateKeyHex
            payload.relayPublicKey = publicKeyHex
        }
    }

    func storePaymentAddress(orderId: String, paymentAddress: String) throws {
        try mutate { $0.paymentAddresses[orderId] = paymentAddress }
    }

    func storeCheckpointJson(value: String) throws {
        try mutate { $0.checkpointJSON = value }
    }

    func clearCheckpoint() throws {
        try mutate { $0.checkpointJSON = nil }
    }

    func storeTopUpCheckpointJson(value: String) throws {
        try mutate { $0.topUpCheckpointJSON = value }
    }

    func clearTopUpCheckpoint() throws {
        try mutate { $0.topUpCheckpointJSON = nil }
    }

    func storeRefundCheckpointJson(value: String) throws {
        try mutate { $0.refundCheckpointJSON = value }
    }

    func clearRefundCheckpoint() throws {
        try mutate { $0.refundCheckpointJSON = nil }
    }

    private func withPayload<T>(_ body: (OfframpStoragePayload) -> T?) throws -> T? {
        lock.lock()
        defer { lock.unlock() }
        return body(try load())
    }

    private func mutate(_ body: (inout OfframpStoragePayload) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var payload = try load()
        body(&payload)
        try store(payload)
    }

    private func load() throws -> OfframpStoragePayload {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return OfframpStoragePayload() }
        let data = try Data(contentsOf: fileURL)
        guard data.count > 40 else { throw OfframpStorageError.invalidEnvelope }

        let version = data.prefix(8).reduce(0) { ($0 << 8) | Int($1) }
        guard version == OfframpStoragePayload.version else { throw OfframpStorageError.unsupportedVersion(version) }
        let salt = data.subdata(in: 8..<40)
        let subKey = key.deriveEncryptionKey(salt: salt)
        let sealed = try ChaChaPoly.SealedBox(combined: data.subdata(in: 40..<data.count))
        let plaintext = try ChaChaPoly.open(sealed, using: subKey)
        let payload = try JSONDecoder().decode(OfframpStoragePayload.self, from: plaintext)
        guard payload.version == OfframpStoragePayload.version else {
            throw OfframpStorageError.unsupportedVersion(payload.version)
        }
        return payload
    }

    private func store(_ payload: OfframpStoragePayload) throws {
        let saltKey = SymmetricKey(size: .bits256)
        let salt = saltKey.withUnsafeBytes { Data($0) }
        let subKey = key.deriveEncryptionKey(salt: salt)
        let plaintext = try JSONEncoder().encode(payload)
        let sealed = try ChaChaPoly.seal(plaintext, using: subKey)
        let version = withUnsafeBytes(of: UInt64(OfframpStoragePayload.version).bigEndian, Array.init)
        try (Data(version) + salt + sealed.combined).write(
            to: fileURL,
            options: [.atomic, .completeFileProtection]
        )
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedURL = fileURL
        try protectedURL.setResourceValues(resourceValues)
    }
}
