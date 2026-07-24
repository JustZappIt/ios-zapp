//
//  AppSecurityLiveKey.swift
//  Zashi
//

import ComposableArchitecture
import Foundation

extension AppSecurityClient: DependencyKey {
    private enum Constants {
        static let lockoutDuration = 30
        static let maximumFailedAttempts = 5
    }

    static let liveValue = Self.live()

    static func live(
        userDefaults: UserDefaultsClient = .live(),
        walletStorage: WalletStorageClient = .live()
    ) -> Self {
        let authenticationMethod: @Sendable () -> AppAuthenticationMethod = {
            if let rawValue = userDefaults.objectForKey(.appAuthenticationMethod) as? String,
                let method = AppAuthenticationMethod(rawValue: rawValue) {
                return method
            }

            let hasExistingWallet = (try? walletStorage.areKeysPresent()) == true
            return hasExistingWallet ? .biometric : .none
        }

        let resetLockout: @Sendable () -> Void = {
            userDefaults.setValue(0, .failedPINAttempts)
            userDefaults.setValue(0.0, .pinLockoutEndTimestamp)
        }

        let configureBiometric: @Sendable () throws -> Void = {
            try walletStorage.removePINHash()
            userDefaults.setValue(AppAuthenticationMethod.biometric.rawValue, .appAuthenticationMethod)
            resetLockout()
        }

        let configurePIN: @Sendable (String) async throws -> Void = { pin in
            let hash = try await Task.detached(priority: .userInitiated) {
                try PINHasher.hash(pin)
            }.value
            try walletStorage.importPINHash(hash)
            userDefaults.setValue(AppAuthenticationMethod.pin.rawValue, .appAuthenticationMethod)
            resetLockout()
        }

        let lockoutRemaining: @Sendable (Date) -> Int = { now in
            let endTimestamp = userDefaults.objectForKey(.pinLockoutEndTimestamp) as? TimeInterval ?? 0
            return max(0, Int(ceil(endTimestamp - now.timeIntervalSince1970)))
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
                if matched {
                    resetLockout()
                    return .success
                }

                let failedAttempts = userDefaults.objectForKey(.failedPINAttempts) as? Int ?? 0
                let nextFailedAttempts = failedAttempts + 1
                if nextFailedAttempts >= Constants.maximumFailedAttempts {
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
        )
    }
}
