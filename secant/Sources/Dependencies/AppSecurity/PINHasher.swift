//
//  PINHasher.swift
//  Zashi
//

import CommonCrypto
import Foundation
import Security

enum PINHasher {
    enum Error: Swift.Error, Equatable {
        case derivationFailed(Int32)
        case randomGenerationFailed(OSStatus)
    }

    private static let derivedKeyLength = 32
    private static let iterations: UInt32 = 100_000
    private static let saltLength = 16
    private static let version = "v2"

    static func hash(_ pin: String) throws -> String {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, saltLength, baseAddress)
        }
        guard status == errSecSuccess else {
            throw Error.randomGenerationFailed(status)
        }
        return try hash(pin, salt: salt)
    }

    static func hash(_ pin: String, salt: Data) throws -> String {
        let derivedKey = try derive(pin, salt: salt)
        return [
            version,
            salt.base64EncodedString().withoutBase64Padding,
            derivedKey.base64EncodedString().withoutBase64Padding
        ]
        .joined(separator: "$")
    }

    static func verify(_ pin: String, against encodedHash: String) -> Bool {
        let parts = encodedHash.split(separator: "$", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0] == Substring(version),
            let salt = Data(base64EncodedWithoutPadding: String(parts[1])),
            let expected = Data(base64EncodedWithoutPadding: String(parts[2])),
            let actual = try? derive(pin, salt: salt),
            actual.count == expected.count
        else {
            return false
        }

        return zip(actual, expected).reduce(UInt8.zero) { difference, bytes in
            difference | (bytes.0 ^ bytes.1)
        } == 0
    }

    private static func derive(_ pin: String, salt: Data) throws -> Data {
        var derivedKey = Data(count: derivedKeyLength)
        let status: Int32 = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                pin.withCString { pinBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinBytes,
                        pin.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedKeyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw Error.derivationFailed(status)
        }
        return derivedKey
    }
}

private extension String {
    var withoutBase64Padding: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

private extension Data {
    init?(base64EncodedWithoutPadding value: String) {
        let paddingCount = (4 - value.count % 4) % 4
        self.init(base64Encoded: value + String(repeating: "=", count: paddingCount))
    }
}
