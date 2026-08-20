// SPDX-License-Identifier: MIT OR Apache-2.0

import CryptoKit
import Foundation
@preconcurrency import ZappOfframp
@preconcurrency import ZcashLightClientKit

private struct OnrampStoragePayload: Codable {
    static let version = 1

    var version = Self.version
    var checkpointJSON: String?
}

enum OnrampStorageError: Error {
    case missingEncryptionKey
    case documentsDirectory
    case invalidEnvelope
    case unsupportedVersion(Int)
}

/// Wallet-scoped encrypted storage for the durable P2P buy checkpoint.
final class OnrampEncryptedStorage: NSObject, AppleOnrampStorage, @unchecked Sendable {
    private let lock = NSLock()
    private let key: AddressBookKey
    private let fileURL: URL

    init(account: Account, walletStorage: WalletStorageClient) throws {
        let keys = try walletStorage.exportAddressBookEncryptionKeys()
        guard let key = keys.getCached(account: account),
              let filename = key.onrampFileIdentifier() else {
            throw OnrampStorageError.missingEncryptionKey
        }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw OnrampStorageError.documentsDirectory
        }
        self.key = key
        self.fileURL = documents.appendingPathComponent(filename)
    }

    func checkpointJson() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.checkpointJSON })
    }

    func storeCheckpointJson(value: String) throws {
        try mutate { $0.checkpointJSON = value }
    }

    func clearCheckpoint() throws {
        try mutate { $0.checkpointJSON = nil }
    }

    private func withPayload<T>(_ body: (OnrampStoragePayload) -> T?) throws -> T? {
        lock.lock()
        defer { lock.unlock() }
        return body(try load())
    }

    private func mutate(_ body: (inout OnrampStoragePayload) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var payload = try load()
        body(&payload)
        try store(payload)
    }

    private func load() throws -> OnrampStoragePayload {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return OnrampStoragePayload() }
        let data = try Data(contentsOf: fileURL)
        guard data.count > 40 else { throw OnrampStorageError.invalidEnvelope }

        let version = data.prefix(8).reduce(0) { ($0 << 8) | Int($1) }
        guard version == OnrampStoragePayload.version else { throw OnrampStorageError.unsupportedVersion(version) }
        let salt = data.subdata(in: 8..<40)
        let subKey = key.deriveEncryptionKey(salt: salt)
        let sealed = try ChaChaPoly.SealedBox(combined: data.subdata(in: 40..<data.count))
        let plaintext = try ChaChaPoly.open(sealed, using: subKey)
        let payload = try JSONDecoder().decode(OnrampStoragePayload.self, from: plaintext)
        guard payload.version == OnrampStoragePayload.version else {
            throw OnrampStorageError.unsupportedVersion(payload.version)
        }
        return payload
    }

    private func store(_ payload: OnrampStoragePayload) throws {
        let saltKey = SymmetricKey(size: .bits256)
        let salt = saltKey.withUnsafeBytes { Data($0) }
        let subKey = key.deriveEncryptionKey(salt: salt)
        let plaintext = try JSONEncoder().encode(payload)
        let sealed = try ChaChaPoly.seal(plaintext, using: subKey)
        let version = withUnsafeBytes(of: UInt64(OnrampStoragePayload.version).bigEndian, Array.init)
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

private extension AddressBookKey {
    func onrampFileIdentifier() -> String? {
        guard let info = "onramp_file_identifier".data(using: .utf8) else {
            fatalError("Unable to prepare onramp_file_identifier")
        }
        let hkdfKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: info, outputByteCount: 32)
        let identifier = hkdfKey.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
        return "zapp-onramp-\(identifier)"
    }
}
