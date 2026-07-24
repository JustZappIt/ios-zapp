//
//  PINHasherTests.swift
//  zodlTests
//

import Foundation
import Testing
@testable import zodl_internal

@Suite struct PINHasherTests {
    @Test func hashMatchesPBKDF2GoldenVector() throws {
        let salt = Data((0 ..< 16).map(UInt8.init))

        let hash = try PINHasher.hash("123456", salt: salt)

        #expect(
            hash == "v2$AAECAwQFBgcICQoLDA0ODw$Pj0kIvAPLMHRutBFgZv7g2ARfVnFiANcQpTzQDrAl6U"
        )
    }

    @Test func verifyAcceptsMatchingPIN() throws {
        let hash = try PINHasher.hash("123456", salt: Data(repeating: 0xA5, count: 16))

        #expect(PINHasher.verify("123456", against: hash))
    }

    @Test func verifyRejectsIncorrectPIN() throws {
        let hash = try PINHasher.hash("123456", salt: Data(repeating: 0xA5, count: 16))

        #expect(!PINHasher.verify("654321", against: hash))
    }

    @Test func verifyRejectsMalformedHash() {
        #expect(!PINHasher.verify("123456", against: "v2$invalid"))
        #expect(!PINHasher.verify("123456", against: "v1$c2FsdA$aGFzaA"))
    }
}
