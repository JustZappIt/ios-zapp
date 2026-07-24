//
//  AppSecurityTestKey.swift
//  Zashi
//

import ComposableArchitecture

extension AppSecurityClient {
    static let noOp = Self(
        authenticationMethod: { .none },
        configureBiometric: { },
        configurePIN: { _ in },
        lockoutRemaining: { _ in 0 },
        verifyPIN: { _, _ in .incorrect }
    )
}
