//
//  AppAuthenticationMethod.swift
//  Zashi
//

enum AppAuthenticationMethod: String, Equatable, Sendable {
    case biometric
    case none
    case pin
}

enum PINVerificationResult: Equatable, Sendable {
    case incorrect
    case locked(secondsRemaining: Int)
    case success
}
