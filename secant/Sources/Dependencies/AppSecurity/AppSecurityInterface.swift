//
//  AppSecurityInterface.swift
//  Zashi
//

import ComposableArchitecture
import Foundation

extension DependencyValues {
    var appSecurity: AppSecurityClient {
        get { self[AppSecurityClient.self] }
        set { self[AppSecurityClient.self] = newValue }
    }
}

@DependencyClient
struct AppSecurityClient {
    var authenticationMethod: @Sendable () -> AppAuthenticationMethod = { .none }
    var configureBiometric: @Sendable () throws -> Void
    var configurePIN: @Sendable (_ pin: String) async throws -> Void
    var lockoutRemaining: @Sendable (_ now: Date) -> Int = { _ in 0 }
    var verifyPIN: @Sendable (_ pin: String, _ now: Date) async -> PINVerificationResult = { _, _ in .incorrect }
}
