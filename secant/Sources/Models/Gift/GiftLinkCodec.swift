// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import MnemonicSwift
import ZcashLightClientKit

/// Bearer payload carried in a gift link's fragment.
///
/// The shape is normative and shared with Android — `zapp-android/docs/gift-cards.md` §2 — so the
/// field names, the integer height and the decimal-string amount are wire contract rather than
/// local choices. `amountZatoshi` is a string because JSON numbers decode to doubles in too many
/// parsers, which would silently round a large card. The card's address is not carried: it is
/// derived from `mnemonic`, so sending it would be 40% of the link spent restating what the link
/// already says.
struct GiftLinkPayload: Codable, Equatable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case version = "v"
        case network
        case amountZatoshi
        case mnemonic
        case birthdayHeight
        case createdAt
        case expiresAt
        case message
    }

    /// The wire field is `v`; only the Swift name differs.
    let version: Int
    let network: String
    let amountZatoshi: String
    let mnemonic: String
    let birthdayHeight: Int64
    let createdAt: String
    let expiresAt: String?
    let message: String?

    init(
        version: Int,
        network: String,
        amountZatoshi: String,
        mnemonic: String,
        birthdayHeight: Int64,
        createdAt: String,
        expiresAt: String? = nil,
        message: String? = nil
    ) {
        self.version = version
        self.network = network
        self.amountZatoshi = amountZatoshi
        self.mnemonic = mnemonic
        self.birthdayHeight = birthdayHeight
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.message = message
    }
}

// The mnemonic is the money, and a generated description reaches every log line and crash report
// that interpolates the payload.
extension GiftLinkPayload: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "GiftLinkPayload(v=\(version), network=\(network), redacted)" }
    var debugDescription: String { description }
}

/// Why a link was rejected. Each case is a distinct thing to tell the recipient.
enum GiftLinkError: Error, Equatable {
    /// Over `GiftLinkCodec.maxURIBytes`, by character count or by UTF-8 byte size.
    case tooLarge

    /// Not a gift link at all: wrong scheme, host or path, or no usable fragment.
    case malformedURI

    /// The fragment did not decode to JSON we understand — bad base64, bad JSON, or bad types.
    case malformedPayload

    /// A link version this build does not know how to claim.
    case unsupportedVersion

    /// Version 1, but carrying fields this build does not recognise, so it was written by
    /// something newer. Still refused — the money is real and we cannot know what the extra field
    /// changes — but told apart from `malformedPayload` because the remedy is a different one:
    /// update, do not go back to the sender saying their gift is broken.
    case newerFormat

    /// A mainnet card on a testnet wallet, or the reverse.
    case networkMismatch

    case invalidAmount

    case invalidMnemonic

    /// Non-positive, or below the network's Sapling activation.
    case invalidBirthday

    /// Claims to have been created above the current chain tip.
    case birthdayAboveTip

    case invalidCreatedAt

    case messageTooLong
}

/// What scanning back to a card's birthday would cost the recipient.
enum GiftBirthdayVerdict: Equatable {
    /// Recent enough to scan without asking.
    case proceed

    /// Far enough back that the recipient must opt into the scan.
    case needsConsent(blocksToScan: Int64)
}

/// Encodes and decodes gift links.
///
/// Pure — no network, no key derivation, no synchronizer — so every rule here is unit-testable
/// instantly. It imports the SDK for `Zatoshi`/`NetworkType` constants only, mirroring Android's
/// codec importing SDK models.
///
/// The bearer secret rides in the fragment rather than the query because everything after `#` is
/// never put on the wire by an HTTP client: it reaches no server, proxy, `Referer` header or
/// link-preview crawler.
///
/// Never log a URI, a payload or a mnemonic from here, at any level, including error paths.
enum GiftLinkCodec {
    static let version = 1

    /// Bound on anything we will even attempt to decode.
    static let maxURIBytes = 16 * 1024

    /// How far back a birthday may sit before the recipient has to consent to the scan.
    static let silentScanBlocks: Int64 = 100_000

    /// Host serving gift links. Three things must name it identically or a tapped link silently
    /// stops opening the app: this constant, the associated-domains entitlement, and the AASA the
    /// host serves. The host is `zapp-gift-host`, deployed to Cloudflare Pages; bumping `version`
    /// means shipping the matching `public/c/vN` page in the same change, or a recipient without
    /// the app meets a 404 holding a link that is real money.
    static let giftLinkHost = "gift.justzappit.xyz"

    private static let scheme = "https"
    private static let linkPath = "/c/v1"
    private static let fragmentPrefix = "k="
    private static let mnemonicWordCount = 24
    private static let networkMain = "main"
    private static let networkTest = "test"
    private static let fieldVersion = "v"

    /// Every field a v1 link may carry — normative with Android. Adding one to `GiftLinkPayload`
    /// without adding it here refuses links this build itself produces, so the two are kept in
    /// step by `GiftLinkCodecTests`.
    private static let knownFields: Set<String> = [
        fieldVersion,
        "network",
        "amountZatoshi",
        "mnemonic",
        "birthdayHeight",
        "createdAt",
        "expiresAt",
        "message"
    ]

    /// The link's name for `network`, or nil for a network gift cards do not support.
    static func networkName(_ network: NetworkType) -> String? {
        switch network {
        case .mainnet: return networkMain
        case .testnet: return networkTest
        case .regtest: return nil
        }
    }

    /// Both bounds, in this order: character count cannot bound the byte size, while measuring
    /// bytes first would mean copying whatever we were handed.
    static func isWithinSizeLimit(_ uri: String) -> Bool {
        uri.count <= maxURIBytes && uri.utf8.count <= maxURIBytes
    }

    /// Builds the shareable link, validating first: a link we would refuse to decode is a card
    /// whose funds nobody can ever reach.
    static func encode(_ payload: GiftLinkPayload) throws -> String {
        let normalized = payload.normalized()
        try validateShape(normalized)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let body = base64URLEncode(try encoder.encode(normalized))
        return "\(scheme)://\(giftLinkHost)\(linkPath)#\(fragmentPrefix)\(body)"
    }

    /// Parses and validates a link without touching the network.
    static func decode(_ uri: String, walletNetwork: NetworkType) throws -> GiftLinkPayload {
        try ensure(isWithinSizeLimit(uri), .tooLarge)

        let decoded = try payloadData(from: uri)

        // Read the shape before the values. A strict decode refuses an unrecognised field — which
        // is the right call on a link that carries spendable money — but it cannot say *why* it
        // refused without quoting the input, and the input is the bearer mnemonic. Inspecting the
        // key set first is what lets the two cases be told apart: gibberish, and a real link from
        // a build that knows something this one does not.
        guard let fields = (try? JSONSerialization.jsonObject(with: decoded)) as? [String: Any] else {
            throw GiftLinkError.malformedPayload
        }

        // Before the unknown-field check, so a v2 link reports its version rather than its extras.
        try ensure(intValue(fields[fieldVersion]) == version, .unsupportedVersion)
        try ensure(fields.keys.allSatisfy { knownFields.contains($0) }, .newerFormat)

        guard let payload = try? JSONDecoder().decode(GiftLinkPayload.self, from: decoded) else {
            // Never chain or quote the decoder's error: it embeds a snippet of the input it failed
            // on, which here is the bearer mnemonic.
            throw GiftLinkError.malformedPayload
        }

        let normalized = payload.normalized()
        try validateShape(normalized)
        try ensure(normalized.network == networkName(walletNetwork), .networkMismatch)
        return normalized
    }

    /// Decides what scanning back to a card's birthday costs, given the current chain tip.
    ///
    /// Deliberately does not clamp. A note is only found by trial-decrypting the block that
    /// carries it, so a birthday clamped past the funding height finds nothing and the claim fails
    /// on a perfectly good card. With no reclaim that burns the funds, and it quietly reinstates
    /// the hard expiry the design rejects. Bound the scan by asking the recipient, never by moving
    /// the height.
    static func evaluateBirthday(_ birthdayHeight: Int64, chainTip: Int64) throws -> GiftBirthdayVerdict {
        try ensure(birthdayHeight <= chainTip, .birthdayAboveTip)
        return birthdayHeight >= chainTip - silentScanBlocks
            ? .proceed
            : .needsConsent(blocksToScan: chainTip - birthdayHeight)
    }

    /// Accepts both second and fractional-second precision, so a peer's `Instant.toString()`
    /// parses either way.
    static func parseInstant(_ value: String) -> Date? {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    static func instantString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// The link's payload bytes: every check that this URI is one of ours, then the base64 body.
    private static func payloadData(from uri: String) throws -> Data {
        guard let parsed = URLComponents(string: uri) else { throw GiftLinkError.malformedURI }
        try ensure(parsed.scheme?.lowercased() == scheme, .malformedURI)
        try ensure(parsed.host?.lowercased() == giftLinkHost, .malformedURI)
        try ensure(parsed.path == linkPath, .malformedURI)
        // A gift link never carries a query. One here means something rewrote the link, and
        // whatever it wrote was seen by every server on the way.
        try ensure(parsed.percentEncodedQuery == nil, .malformedURI)
        let fragment = parsed.percentEncodedFragment ?? ""
        try ensure(fragment.hasPrefix(fragmentPrefix), .malformedURI)
        guard let data = base64URLDecode(String(fragment.dropFirst(fragmentPrefix.count))) else {
            throw GiftLinkError.malformedPayload
        }
        return data
    }

    private static func validateShape(_ payload: GiftLinkPayload) throws {
        try ensure(payload.version == version, .unsupportedVersion)

        let network: ZcashNetwork
        switch payload.network {
        case networkMain: network = ZcashNetworkBuilder.network(for: .mainnet)
        case networkTest: network = ZcashNetworkBuilder.network(for: .testnet)
        default: throw GiftLinkError.networkMismatch
        }

        // Bound-check the raw Int64 before any `Zatoshi` is constructed: the Zatoshi initializer
        // clamps out-of-range values silently, which would rewrite a hostile amount instead of
        // rejecting it.
        let amount = Int64(payload.amountZatoshi)
        try ensure(amount.map { $0 > 0 && $0 <= Zatoshi.Constants.maxZatoshi } == true, .invalidAmount)

        try validateMnemonic(payload.mnemonic)

        try ensure(
            payload.birthdayHeight > 0 && payload.birthdayHeight >= Int64(network.saplingActivationHeight),
            .invalidBirthday
        )

        try ensure(parseInstant(payload.createdAt) != nil, .invalidCreatedAt)

        // expiresAt is deliberately not rejected when unparseable. It is advisory — nothing on
        // chain enforces it — so a peer's clock or formatting must never become the reason a
        // funded card cannot be claimed. Readers treat what they cannot parse as absent.

        if let message = payload.message {
            try ensure(GiftMessage.isWithinLimits(message), .messageTooLong)
        }
    }

    private static func validateMnemonic(_ mnemonic: String) throws {
        let wordCount = mnemonic.split(separator: " ").count
        try ensure(wordCount == mnemonicWordCount && (try? Mnemonic.validate(mnemonic: mnemonic)) != nil, .invalidMnemonic)
    }

    /// Mirrors Android reading the raw `v` primitive: a JSON int, or a string spelling one.
    private static func intValue(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int(exactly: number)
        }
        return (raw as? String).flatMap(Int.init)
    }

    // Unpadded on encode, tolerant of padding on decode.
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ body: String) -> Data? {
        var standard = body
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: standard)
    }

    private static func ensure(_ condition: Bool, _ error: GiftLinkError) throws {
        if !condition { throw error }
    }
}

extension GiftLinkPayload {
    /// Trims every string; additionally collapses whitespace runs in the mnemonic: a phrase that
    /// survived a copy-paste through a chat client is still the same 24 words, and BIP-39 wants
    /// them single-spaced.
    func normalized() -> GiftLinkPayload {
        GiftLinkPayload(
            version: version,
            network: network.trimmed(),
            amountZatoshi: amountZatoshi.trimmed(),
            mnemonic: mnemonic.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            birthdayHeight: birthdayHeight,
            createdAt: createdAt.trimmed(),
            expiresAt: expiresAt?.trimmed(),
            message: message?.trimmed()
        )
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
