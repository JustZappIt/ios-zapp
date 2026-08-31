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
    /// Peer's two books, opaque here: their shape, their locking and their privacy rules live in
    /// the KMP facade, so there is one implementation of them rather than one per platform.
    /// Optional, so a payload written before Peer existed still decodes.
    var peerCheckpointBookJSON: String?
    var peerPayeeBookJSON: String?
}

enum OfframpStorageError: Error {
    case missingEncryptionKey
    case documentsDirectory
    case invalidEnvelope
    case unsupportedVersion(Int)
}

/// A file is the unit of consistency, not a storage object. KMP creates separate rail facades, and
/// nothing prevents another caller from constructing a second Swift adapter for the same wallet.
/// Keeping the mutexes here makes every whole-payload read-modify-write share one critical section
/// even when those adapters have different lifetimes.
private final class OfframpStorageLockRegistry: @unchecked Sendable {
    static let shared = OfframpStorageLockRegistry()

    private let registryLock = NSLock()
    private var locks: [String: NSLock] = [:]

    func lock(for fileURL: URL) -> NSLock {
        // Resolve the parent because the file usually does not exist when the first adapter is
        // built. Standardizing only the leaf would still let a symlinked Documents path create a
        // second identity for the same encrypted envelope.
        let parent = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let identity = parent.appendingPathComponent(fileURL.lastPathComponent).path
        return registryLock.withLock {
            if let lock = locks[identity] { return lock }
            let lock = NSLock()
            locks[identity] = lock
            return lock
        }
    }
}

/// Wallet-scoped encrypted storage. Unknown payload versions throw and are never overwritten.
///
/// Peer shares this file rather than opening its own. Both rails spend from one Base smart account,
/// so their records are only ever read and written together, and a second envelope would mean a
/// second lock, a second key and a second chance for a wallet reset to clear one and miss the other.
final class OfframpEncryptedStorage: NSObject, AppleOfframpStorage, ApplePeerCashOutStorage, @unchecked Sendable {
    private let lock: NSLock
    private let key: AddressBookKey
    private let fileURL: URL

    /// A deterministic assertion seam for the concurrency regression: two adapters for one file
    /// must literally share the same mutex, independent of how the scheduler interleaves writes.
    var lockIdentityForTesting: ObjectIdentifier { ObjectIdentifier(lock) }

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
        self.lock = OfframpStorageLockRegistry.shared.lock(for: fileURL)
    }

    /// Direct construction keeps file-identity concurrency tests out of the user's Documents
    /// directory. Production always uses the wallet-scoped initializer above.
    init(key: AddressBookKey, fileURL: URL) {
        self.key = key
        self.fileURL = fileURL
        self.lock = OfframpStorageLockRegistry.shared.lock(for: fileURL)
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

    // MARK: - Peer

    func peerCheckpointBookJson() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.peerCheckpointBookJSON })
    }

    func storePeerCheckpointBookJson(value: String) throws {
        try mutate { $0.peerCheckpointBookJSON = value }
    }

    func peerPayeeBookJson() throws -> AppleStorageValue {
        AppleStorageValue(value: try withPayload { $0.peerPayeeBookJSON })
    }

    /// Raw payment handles. They never reach a checkpoint, a log, a diagnostic or a support export
    /// — only the curator hash does — so this slot is the one place they exist on the device.
    func storePeerPayeeBookJson(value: String) throws {
        try mutate { $0.peerPayeeBookJSON = value }
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
        // The atomic write is the commit point observed by KMP. Neither metadata write below may
        // turn a committed broadcast marker into a reported failure — that ambiguity could leave a
        // never-broadcast identity reserved forever on the next launch — and neither needs to:
        // protection is already requested above, and backup exclusion is a privacy hardening on a
        // file whose contents are encrypted with a wallet-scoped key.
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedURL = fileURL
        try? protectedURL.setResourceValues(resourceValues)
    }
}
