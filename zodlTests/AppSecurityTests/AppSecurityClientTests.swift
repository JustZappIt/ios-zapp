//
//  AppSecurityClientTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite struct AppSecurityClientTests {
    @Test func fifthFailedAttemptStartsPersistedLockout() async throws {
        let suiteName = "AppSecurityClientTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storedHash = LockIsolated<String?>(nil)
        var walletStorage = WalletStorageClient.noOp
        walletStorage.importPINHash = { storedHash.setValue($0) }
        walletStorage.exportPINHash = { storedHash.value }
        walletStorage.removePINHash = { storedHash.setValue(nil) }

        let client = AppSecurityClient.live(
            userDefaults: .live(userDefaults: defaults),
            walletStorage: walletStorage
        )
        let now = Date(timeIntervalSince1970: 1_000)

        try await client.configurePIN("123456")
        #expect(client.authenticationMethod() == .pin)

        for _ in 0 ..< 4 {
            #expect(await client.verifyPIN("000000", now) == .incorrect)
        }
        #expect(await client.verifyPIN("000000", now) == .locked(secondsRemaining: 30))
        #expect(await client.verifyPIN("123456", now) == .locked(secondsRemaining: 30))
        #expect(await client.verifyPIN("123456", now.addingTimeInterval(31)) == .success)
    }

    @Test func existingWalletWithoutPreferenceUsesBiometricMigrationDefault() {
        var walletStorage = WalletStorageClient.noOp
        walletStorage.areKeysPresent = { true }

        let client = AppSecurityClient.live(
            userDefaults: .noOp,
            walletStorage: walletStorage
        )

        #expect(client.authenticationMethod() == .biometric)
    }

    @Test func concurrentFailuresCountTowardOneLockout() async throws {
        let suiteName = "AppSecurityClientTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storedHash = LockIsolated<String?>(nil)
        var walletStorage = WalletStorageClient.noOp
        walletStorage.importPINHash = { storedHash.setValue($0) }
        walletStorage.exportPINHash = { storedHash.value }
        walletStorage.removePINHash = { storedHash.setValue(nil) }

        let client = AppSecurityClient.live(
            userDefaults: .live(userDefaults: defaults),
            walletStorage: walletStorage
        )
        let now = Date(timeIntervalSince1970: 1_000)

        try await client.configurePIN("123456")
        let results = await withTaskGroup(
            of: PINVerificationResult.self,
            returning: [PINVerificationResult].self
        ) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    await client.verifyPIN("000000", now)
                }
            }

            var results: [PINVerificationResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(results.filter { $0 == .incorrect }.count == 4)
        #expect(results.filter { $0 == .locked(secondsRemaining: 30) }.count == 1)
        #expect(client.lockoutRemaining(now) == 30)
    }
}
