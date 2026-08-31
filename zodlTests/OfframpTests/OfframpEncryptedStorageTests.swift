// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

struct OfframpEncryptedStorageTests {
    /// Peer and p2p.me have separate KMP facades but mutate one encrypted payload. Releasing both
    /// writers from the same barrier exercises the file-identity lock: neither whole-payload write
    /// may replace the field the other rail just stored.
    @Test func concurrentRailMutationsPreserveBothRecoveryRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("offramp-recovery")
        let key = try addressBookKey(byte: 0x42)
        let legacyStorage = OfframpEncryptedStorage(key: key, fileURL: fileURL)
        let peerStorage = OfframpEncryptedStorage(key: key, fileURL: fileURL)
        let barrier = ConcurrentMutationBarrier(participants: 2)
        let legacyCheckpoint = String(repeating: "legacy-rail", count: 4_096)
        let peerCheckpoint = String(repeating: "peer-rail", count: 4_096)

        // This makes the regression deterministic: the old per-instance locks fail even on a run
        // where the two whole-payload writes happen not to overlap after the barrier.
        #expect(legacyStorage.lockIdentityForTesting == peerStorage.lockIdentityForTesting)

        let legacyWrite = Task.detached {
            await barrier.arriveAndWait()
            try legacyStorage.storeCheckpointJson(value: legacyCheckpoint)
        }
        let peerWrite = Task.detached {
            await barrier.arriveAndWait()
            try peerStorage.storePeerCheckpointBookJson(value: peerCheckpoint)
        }

        try await legacyWrite.value
        try await peerWrite.value

        #expect(try legacyStorage.checkpointJson().value == legacyCheckpoint)
        #expect(try peerStorage.peerCheckpointBookJson().value == peerCheckpoint)
    }

    private func addressBookKey(byte: UInt8) throws -> AddressBookKey {
        let encoded = try JSONEncoder().encode(Data(repeating: byte, count: 32))
        return try JSONDecoder().decode(AddressBookKey.self, from: encoded)
    }
}

private actor ConcurrentMutationBarrier {
    let participants: Int

    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participants: Int) {
        self.participants = participants
    }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals == participants {
            let waiters = waiters
            self.waiters.removeAll()
            waiters.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}
