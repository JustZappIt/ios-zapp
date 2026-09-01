// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ZcashLightClientKit
@testable import zodl_internal

@Suite struct GiftLinkCodecTests {
    /// BIP-39 test vector for all-zero entropy. Never a real wallet.
    private static let mnemonic =
        "\(String(repeating: "abandon ", count: 23))art"

    private static let address = "u1exampleunifiedaddressforgiftcardtests"
    private static let birthday: Int64 = 2_800_000
    private static let tip: Int64 = 3_000_000

    @Test func roundTripsAPayloadThroughALink() throws {
        let payload = payload()

        let decoded = try GiftLinkCodec.decode(try GiftLinkCodec.encode(payload), walletNetwork: .mainnet)

        #expect(decoded == payload)
    }

    @Test func roundTripsOptionalFieldsBothPresentAndAbsent() throws {
        let bare = payload(expiresAt: nil, message: nil)
        let full = payload(expiresAt: "2026-12-24T00:00:00Z", message: "happy birthday")

        #expect(try GiftLinkCodec.decode(try GiftLinkCodec.encode(bare), walletNetwork: .mainnet) == bare)
        #expect(try GiftLinkCodec.decode(try GiftLinkCodec.encode(full), walletNetwork: .mainnet) == full)
    }

    @Test func encodesToTheSharedLinkShape() throws {
        let link = try GiftLinkCodec.encode(payload())

        #expect(link.hasPrefix("https://\(GiftLinkCodec.giftLinkHost)/c/v1#k="))
        // The secret must sit in the fragment, where no HTTP client ever puts it on the wire.
        let beforeFragment = link.split(separator: "#").first.map(String.init) ?? ""
        #expect(!beforeFragment.contains("k="))
    }

    @Test func encodesBase64URLUnpaddedAcrossEveryRemainderLength() throws {
        // Walking the message length by one walks the payload length by one, so this covers inputs
        // whose byte count leaves each of the three possible remainders mod 3.
        for extra in 0...3 {
            let payload = payload(message: String(repeating: "m", count: extra))
            let link = try GiftLinkCodec.encode(payload)
            let body = link.components(separatedBy: "#k=").last ?? ""

            #expect(!body.contains("="), "padding leaked for message length \(extra)")
            #expect(!body.contains("+") && !body.contains("/"), "non-url-safe alphabet for length \(extra)")
            #expect(try GiftLinkCodec.decode(link, walletNetwork: .mainnet) == payload)
        }
    }

    @Test func acceptsAPaddedFragmentOnDecode() throws {
        let payload = payload()
        let padded = Data(jsonOf(payload).utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // Only meaningful if this input actually needed padding.
        try #require(padded.hasSuffix("="))
        let link = "https://\(GiftLinkCodec.giftLinkHost)/c/v1#k=\(padded)"
        #expect(try GiftLinkCodec.decode(link, walletNetwork: .mainnet) == payload)
    }

    @Test func rejectsAURIOverTheSizeBoundByCharacterCount() {
        let link = "https://\(GiftLinkCodec.giftLinkHost)/c/v1#k=\(String(repeating: "A", count: GiftLinkCodec.maxURIBytes + 1))"

        #expect(decodeError(link) == .tooLarge)
    }

    @Test func rejectsAURIOverTheSizeBoundByUTF8BytesAlone() {
        // Under the bound by character count, over it by byte size: checking only the count would
        // let this through.
        let body = String(repeating: "é", count: GiftLinkCodec.maxURIBytes - 1000)
        let link = "https://\(GiftLinkCodec.giftLinkHost)/c/v1#k=\(body)"

        #expect(link.count <= GiftLinkCodec.maxURIBytes)
        #expect(link.utf8.count > GiftLinkCodec.maxURIBytes)
        #expect(decodeError(link) == .tooLarge)
    }

    @Test func rejectsLinksThatAreNotOurs() {
        let body = base64URL(jsonOf(payload()))
        let host = GiftLinkCodec.giftLinkHost

        #expect(decodeError("http://\(host)/c/v1#k=\(body)") == .malformedURI)
        #expect(decodeError("https://evil.example.com/c/v1#k=\(body)") == .malformedURI)
        #expect(decodeError("https://\(host)/c/v2#k=\(body)") == .malformedURI)
        #expect(decodeError("https://\(host)/c/v1") == .malformedURI)
        #expect(decodeError("https://\(host)/c/v1#\(body)") == .malformedURI)
        #expect(decodeError("not a uri at all") == .malformedURI)
    }

    @Test func rejectsALinkCarryingThePayloadInTheQuery() {
        let body = base64URL(jsonOf(payload()))

        #expect(decodeError("https://\(GiftLinkCodec.giftLinkHost)/c/v1?k=\(body)#k=\(body)") == .malformedURI)
    }

    @Test func matchesTheHostCaseInsensitively() throws {
        let link = try GiftLinkCodec.encode(payload())
            .replacingOccurrences(of: GiftLinkCodec.giftLinkHost, with: GiftLinkCodec.giftLinkHost.uppercased())

        #expect(try GiftLinkCodec.decode(link, walletNetwork: .mainnet) == payload())
    }

    @Test func rejectsAFragmentThatIsNotBase64() {
        #expect(decodeError("https://\(GiftLinkCodec.giftLinkHost)/c/v1#k=not*base64") == .malformedPayload)
    }

    @Test func rejectsAnUnknownFieldAsANewerFormatRatherThanABrokenLink() {
        let json = "\(jsonOf(payload()).dropLast()),\"surprise\":\"tracking-id\"}"

        // Still refused — an unrecognised field could change who may claim, or for how much — but
        // told apart from gibberish. The card is real and there is no reclaim, so the recipient
        // has to be told to update rather than told their gift is broken.
        #expect(decodeError(linkOf(json)) == .newerFormat)
    }

    @Test func reportsAnUnknownVersionEvenWhenItAlsoCarriesUnknownFields() {
        let json = "\(jsonOf(payload(v: 2)).dropLast()),\"surprise\":\"tracking-id\"}"

        // The version is the more specific answer, so it wins the ordering.
        #expect(decodeError(linkOf(json)) == .unsupportedVersion)
    }

    @Test func everyFieldThisBuildEncodesIsOneItRecognisesOnTheWayBackIn() throws {
        // The unknown-field check is a hand-maintained key set, so a field added to the payload
        // and not to it would make this build refuse its own links — on money with no reclaim.
        let everyField = payload(expiresAt: "2027-01-01T00:00:00Z", message: "hi")

        #expect(try GiftLinkCodec.decode(try GiftLinkCodec.encode(everyField), walletNetwork: .mainnet) == everyField)
    }

    @Test func rejectsAMissingRequiredField() {
        let json = jsonOf(payload()).replacingOccurrences(of: "\"mnemonic\":\"\(Self.mnemonic)\",", with: "")

        #expect(decodeError(linkOf(json)) == .malformedPayload)
    }

    @Test func rejectsAnUnknownVersion() {
        #expect(decodeError(linkOf(jsonOf(payload(v: 2)))) == .unsupportedVersion)
        #expect(decodeError(linkOf(jsonOf(payload(v: 0)))) == .unsupportedVersion)
    }

    @Test func rejectsACardMintedForTheOtherNetwork() throws {
        let mainnetLink = try GiftLinkCodec.encode(payload())

        #expect(decodeError(mainnetLink, network: .testnet) == .networkMismatch)
    }

    @Test func rejectsAnUnrecognisedNetworkName() {
        #expect(decodeError(linkOf(jsonOf(payload(network: "regtest")))) == .networkMismatch)
        #expect(decodeError(linkOf(jsonOf(payload(network: "")))) == .networkMismatch)
    }

    @Test func rejectsANonPositiveOrUnparseableAmount() {
        #expect(decodeError(linkOf(jsonOf(payload(amount: "0")))) == .invalidAmount)
        #expect(decodeError(linkOf(jsonOf(payload(amount: "-1")))) == .invalidAmount)
        #expect(decodeError(linkOf(jsonOf(payload(amount: "1.5")))) == .invalidAmount)
        #expect(decodeError(linkOf(jsonOf(payload(amount: "not a number")))) == .invalidAmount)
        // Beyond the money supply, and beyond what Zatoshi will construct without clamping.
        #expect(decodeError(linkOf(jsonOf(payload(amount: "2100000000000001")))) == .invalidAmount)
    }

    @Test func rejectsAMnemonicThatIsNotAValid24WordPhrase() {
        let twelve = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

        #expect(decodeError(linkOf(jsonOf(payload(mnemonic: twelve)))) == .invalidMnemonic)
        // 24 words, wrong checksum word.
        #expect(decodeError(linkOf(jsonOf(payload(mnemonic: Self.mnemonic.replacingOccurrences(of: "art", with: "abandon"))))) == .invalidMnemonic)
        #expect(decodeError(linkOf(jsonOf(payload(mnemonic: Self.mnemonic.replacingOccurrences(of: "art", with: "zzzz"))))) == .invalidMnemonic)
    }

    @Test func normalisesWhitespaceInAMnemonicThatSurvivedACopyPaste() throws {
        let doubled = Self.mnemonic
            .replacingOccurrences(of: " ", with: "  ")
            .replacingOccurrences(of: "art", with: "\\nart")
        let mangled = "  \(doubled)  "

        let decoded = try GiftLinkCodec.decode(linkOf(jsonOf(payload(mnemonic: mangled))), walletNetwork: .mainnet)

        #expect(decoded.mnemonic == Self.mnemonic)
    }

    @Test func rejectsABirthdayBelowSaplingActivationOrAtZero() {
        let belowSapling = Int64(ZcashNetworkBuilder.network(for: .mainnet).saplingActivationHeight) - 1

        #expect(decodeError(linkOf(jsonOf(payload(birthday: belowSapling)))) == .invalidBirthday)
        #expect(decodeError(linkOf(jsonOf(payload(birthday: 0)))) == .invalidBirthday)
        #expect(decodeError(linkOf(jsonOf(payload(birthday: -1)))) == .invalidBirthday)
    }

    @Test func appliesTheSaplingFloorOfTheNetworkNamedInThePayload() throws {
        // Testnet activates far below mainnet, so a height legal on testnet is illegal on mainnet.
        let testnetOnly = Int64(ZcashNetworkBuilder.network(for: .testnet).saplingActivationHeight) + 1
        let json = jsonOf(payload(network: "test", birthday: testnetOnly))

        #expect(try GiftLinkCodec.decode(linkOf(json), walletNetwork: .testnet).birthdayHeight == testnetOnly)
        #expect(decodeError(linkOf(jsonOf(payload(network: "main", birthday: testnetOnly)))) == .invalidBirthday)
    }

    @Test func rejectsAnUnparseableCreatedAt() {
        #expect(decodeError(linkOf(jsonOf(payload(createdAt: "yesterday")))) == .invalidCreatedAt)
    }

    @Test func acceptsAFractionalSecondsCreatedAtFromAPeer() throws {
        // Android writes `Instant.toString()`, which carries millisecond precision.
        let decoded = try GiftLinkCodec.decode(
            linkOf(jsonOf(payload(createdAt: "2026-08-20T12:00:00.123Z"))),
            walletNetwork: .mainnet
        )

        #expect(decoded.createdAt == "2026-08-20T12:00:00.123Z")
    }

    @Test func acceptsAnUnparseableExpiresAtBecauseExpiryIsAdvisory() throws {
        // Nothing on chain enforces expiry, so a peer's clock or formatting must never be the
        // reason a funded card cannot be claimed.
        let decoded = try GiftLinkCodec.decode(linkOf(jsonOf(payload(expiresAt: "whenever"))), walletNetwork: .mainnet)

        #expect(decoded.expiresAt == "whenever")
    }

    @Test func acceptsAMessageAtBothLimitsAndRejectsOnePastEither() throws {
        let atClusterLimit = String(repeating: "😀", count: GiftMessage.maxGraphemes)
        let overClusterLimit = String(repeating: "😀", count: GiftMessage.maxGraphemes + 1)
        // One cluster, 601 bytes: a base letter plus 300 combining accents. Isolates the byte
        // bound, which a cluster count cannot stand in for.
        let overByteLimit = "a\(String(repeating: "\u{0301}", count: 300))"

        #expect(GiftMessage.graphemeCount(atClusterLimit) == GiftMessage.maxGraphemes)
        #expect(atClusterLimit.utf8.count == GiftMessage.maxUTF8Bytes)
        #expect(GiftMessage.graphemeCount(overByteLimit) == 1)
        #expect(overByteLimit.utf8.count > GiftMessage.maxUTF8Bytes)

        let atLimitLink = linkOf(jsonOf(payload(message: atClusterLimit)))
        #expect(try GiftLinkCodec.decode(atLimitLink, walletNetwork: .mainnet).message == atClusterLimit)
        #expect(decodeError(linkOf(jsonOf(payload(message: overClusterLimit)))) == .messageTooLong)
        #expect(decodeError(linkOf(jsonOf(payload(message: overByteLimit)))) == .messageTooLong)
    }

    @Test func countsGraphemeClustersRatherThanUTF16Units() {
        #expect(GiftMessage.graphemeCount("😀") == 1)
        #expect("😀".utf16.count == 2)
        #expect(GiftMessage.graphemeCount("abc") == 3)
        #expect(GiftMessage.graphemeCount("") == 0)
    }

    @Test func refusesToEncodeAPayloadItWouldRefuseToDecode() {
        #expect(encodeError(payload(amount: "0")) == .invalidAmount)
        #expect(encodeError(payload(mnemonic: "not a phrase")) == .invalidMnemonic)
        #expect(encodeError(payload(v: 2)) == .unsupportedVersion)
    }

    @Test func doesNotCarryTheCardAddress() {
        // Derivable from the mnemonic beside it, so carrying it spent 40% of the link restating
        // what the link already said. One that turns up now reads as a newer format.
        let json = "\(jsonOf(payload()).dropLast()),\"address\":\"\(Self.address)\"}"

        #expect(decodeError(linkOf(json)) == .newerFormat)
    }

    @Test func encodedLinksOmitTheAddressField() throws {
        let link = try GiftLinkCodec.encode(payload())
        let body = link.components(separatedBy: "#k=").last ?? ""
        let data = try #require(base64URLDecode(body))
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("\"address\""))
    }

    @Test func proceedsSilentlyForABirthdayInsideTheScanWindow() throws {
        #expect(try GiftLinkCodec.evaluateBirthday(Self.tip, chainTip: Self.tip) == .proceed)
        #expect(try GiftLinkCodec.evaluateBirthday(Self.tip - GiftLinkCodec.silentScanBlocks, chainTip: Self.tip) == .proceed)
    }

    @Test func asksForConsentRatherThanClampingAnOldBirthday() throws {
        let old = Self.tip - GiftLinkCodec.silentScanBlocks - 1

        // Not clamped, not rejected: clamping past the funding height means the note is never
        // trial-decrypted and a perfectly good card claims empty.
        #expect(
            try GiftLinkCodec.evaluateBirthday(old, chainTip: Self.tip)
                == .needsConsent(blocksToScan: GiftLinkCodec.silentScanBlocks + 1)
        )
    }

    @Test func rejectsABirthdayAboveTheChainTip() {
        #expect(throws: GiftLinkError.birthdayAboveTip) {
            try GiftLinkCodec.evaluateBirthday(Self.tip + 1, chainTip: Self.tip)
        }
    }

    @Test func namesEachSupportedNetwork() {
        #expect(GiftLinkCodec.networkName(.mainnet) == "main")
        #expect(GiftLinkCodec.networkName(.testnet) == "test")
        #expect(GiftLinkCodec.networkName(.regtest) == nil)
    }

    @Test func keepsTheMnemonicOutOfDescriptions() {
        let payload = payload()

        #expect(!payload.description.contains("abandon"))
        #expect(!payload.debugDescription.contains("abandon"))
        #expect(!"\(payload)".contains("abandon"))
    }

    private func decodeError(_ link: String, network: NetworkType = .mainnet) -> GiftLinkError? {
        do {
            _ = try GiftLinkCodec.decode(link, walletNetwork: network)
            return nil
        } catch let error as GiftLinkError {
            return error
        } catch {
            return nil
        }
    }

    private func encodeError(_ payload: GiftLinkPayload) -> GiftLinkError? {
        do {
            _ = try GiftLinkCodec.encode(payload)
            return nil
        } catch let error as GiftLinkError {
            return error
        } catch {
            return nil
        }
    }

    private func linkOf(_ json: String) -> String {
        "https://\(GiftLinkCodec.giftLinkHost)/c/v1#k=\(base64URL(json))"
    }

    private func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func base64URLDecode(_ body: String) -> Data? {
        var standard = body
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: standard)
    }

    /// Hand-rolled so tests can build payloads the codec would refuse to encode — an unknown
    /// version, a missing field, a fifth network.
    private func jsonOf(_ payload: GiftLinkPayload) -> String {
        var fields = [
            "\"v\":\(payload.version)",
            "\"network\":\"\(payload.network)\"",
            "\"amountZatoshi\":\"\(payload.amountZatoshi)\"",
            "\"mnemonic\":\"\(payload.mnemonic)\"",
            "\"birthdayHeight\":\(payload.birthdayHeight)",
            "\"createdAt\":\"\(payload.createdAt)\""
        ]
        if let expiresAt = payload.expiresAt {
            fields.append("\"expiresAt\":\"\(expiresAt)\"")
        }
        if let message = payload.message {
            fields.append("\"message\":\"\(message)\"")
        }
        return "{\(fields.joined(separator: ","))}"
    }

    private func payload(
        v: Int = GiftLinkCodec.version,
        network: String = "main",
        amount: String = "100000000",
        mnemonic: String = mnemonic,
        birthday: Int64 = birthday,
        createdAt: String = "2026-08-20T12:00:00Z",
        expiresAt: String? = nil,
        message: String? = nil
    ) -> GiftLinkPayload {
        GiftLinkPayload(
            version: v,
            network: network,
            amountZatoshi: amount,
            mnemonic: mnemonic,
            birthdayHeight: birthday,
            createdAt: createdAt,
            expiresAt: expiresAt,
            message: message
        )
    }
}
