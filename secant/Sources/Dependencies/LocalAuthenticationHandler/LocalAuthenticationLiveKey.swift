//
//  LocalAuthenticationLiveKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 12.11.2022.
//

import ComposableArchitecture
import LocalAuthentication

extension LocalAuthenticationClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        Self(
            authenticate: {
#if targetEnvironment(simulator)
                // Bypass on sim unless e2e launches with
                // `-zodlE2EBiometric YES` to force the real path.
                if !UserDefaults.standard.bool(forKey: "zodlE2EBiometric") {
                    return true
                }
#endif
                let context = LAContext()
                var error: NSError?
                let reason = String(localizable: .localAuthenticationReason)

                do {
                    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                        return false
                    }
                    return try await context.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: reason
                    )
                } catch {
                    return false
                }
            },
            method: {
                let context = LAContext()
                var error: NSError?

                if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                    switch context.biometryType {
                    case .faceID:
                        return .faceID
                    case .touchID:
                        return .touchID
                    case .none, .opticID:
                        return .none
                    @unknown default:
                        return .none
                    }
                } else {
                    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                        return .passcode
                        } else {
                            return .none
                        }
                }
            }
        )
    }
}
