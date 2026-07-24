//
//  AppSecurityLiveKey.swift
//  Zashi
//

import ComposableArchitecture
import Foundation

extension AppSecurityClient: DependencyKey {
    static let liveValue = Self.live()

    static func live(
        userDefaults: UserDefaultsClient = .live(),
        walletStorage: WalletStorageClient = .live()
    ) -> Self {
        let lockoutState = PINLockoutState(userDefaults: userDefaults)
        let authenticationMethod: @Sendable () -> AppAuthenticationMethod = {
            if let rawValue = userDefaults.objectForKey(.appAuthenticationMethod) as? String,
                let method = AppAuthenticationMethod(rawValue: rawValue) {
                return method
            }

            let hasExistingWallet = (try? walletStorage.areKeysPresent()) == true
            return hasExistingWallet ? .biometric : .none
        }

        let configureBiometric: @Sendable () throws -> Void = {
            try walletStorage.removePINHash()
            userDefaults.setValue(AppAuthenticationMethod.biometric.rawValue, .appAuthenticationMethod)
            lockoutState.reset()
        }

        let configurePIN: @Sendable (String) async throws -> Void = { pin in
            let hash = try await Task.detached(priority: .userInitiated) {
                try PINHasher.hash(pin)
            }.value
            try walletStorage.importPINHash(hash)
            userDefaults.setValue(AppAuthenticationMethod.pin.rawValue, .appAuthenticationMethod)
            lockoutState.reset()
        }

        let lockoutRemaining: @Sendable (Date) -> Int = { now in
            lockoutState.remaining(at: now)
        }

        return Self(
            authenticationMethod: authenticationMethod,
            configureBiometric: configureBiometric,
            configurePIN: configurePIN,
            lockoutRemaining: lockoutRemaining,
            verifyPIN: { pin, now in
                let remaining = lockoutRemaining(now)
                guard remaining == 0 else {
                    return .locked(secondsRemaining: remaining)
                }

                let storedHash = try? walletStorage.exportPINHash()
                let matched = if let storedHash {
                    await Task.detached(priority: .userInitiated) {
                        PINHasher.verify(pin, against: storedHash)
                    }.value
                } else {
                    false
                }
                return lockoutState.verificationResult(matched: matched, at: now)
            }
        )
    }
}

private final class PINLockoutState: @unchecked Sendable {
    private enum Constants {
        static let lockoutDuration = 30
        static let maximumFailedAttempts = 5
    }

    private let lock = NSLock()
    private let userDefaults: UserDefaultsClient

    init(userDefaults: UserDefaultsClient) {
        self.userDefaults = userDefaults
    }

    func remaining(at now: Date) -> Int {
        lock.withLock {
            remainingWithoutLock(at: now)
        }
    }

    func reset() {
        lock.withLock {
            resetWithoutLock()
        }
    }

    func verificationResult(matched: Bool, at now: Date) -> PINVerificationResult {
        lock.withLock {
            let remaining = remainingWithoutLock(at: now)
            guard remaining == 0 else {
                return .locked(secondsRemaining: remaining)
            }

            guard !matched else {
                resetWithoutLock()
                return .success
            }

            let failedAttempts = userDefaults.objectForKey(.failedPINAttempts) as? Int ?? 0
            let nextFailedAttempts = failedAttempts + 1
            guard nextFailedAttempts < Constants.maximumFailedAttempts else {
                userDefaults.setValue(0, .failedPINAttempts)
                userDefaults.setValue(
                    now.addingTimeInterval(TimeInterval(Constants.lockoutDuration)).timeIntervalSince1970,
                    .pinLockoutEndTimestamp
                )
                return .locked(secondsRemaining: Constants.lockoutDuration)
            }

            userDefaults.setValue(nextFailedAttempts, .failedPINAttempts)
            return .incorrect
        }
    }

    private func remainingWithoutLock(at now: Date) -> Int {
        let endTimestamp = userDefaults.objectForKey(.pinLockoutEndTimestamp) as? TimeInterval ?? 0
        return max(0, Int(ceil(endTimestamp - now.timeIntervalSince1970)))
    }

    private func resetWithoutLock() {
        userDefaults.setValue(0, .failedPINAttempts)
        userDefaults.setValue(0.0, .pinLockoutEndTimestamp)
    }
}
