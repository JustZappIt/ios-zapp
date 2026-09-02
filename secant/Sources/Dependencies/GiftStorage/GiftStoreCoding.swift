// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// The gift store blob could not be read as the only copy of custody data it is.
///
/// Distinct from "absent" on purpose: a mutation reads before it writes, so a refused read refuses
/// the write — treating corrupt as absent would let the next write replace a list of funded cards
/// with a list of one.
struct GiftStoreCorrupt: Error, Equatable {
    let message: String
}

/// Strict Codable discipline for the two gift keychain blobs.
///
/// Swift's `JSONDecoder` silently ignores unknown keys — the dangerous behavior here, because an
/// older build decoding tolerantly would drop a newer build's field and then rewrite the blob
/// without it, silently discarding part of the only copy of a card's recovery data. So every
/// object's key set is checked against the model's known keys before the typed decode, and the
/// write path re-reads its own encoding so an encoder/decoder asymmetry is caught before it
/// becomes the only copy.
enum GiftStoreCoding {
    static func encodeGiftCards(_ cards: [StoredGiftCard]) throws -> Data {
        let data: Data
        do {
            data = try JSONEncoder().encode(cards)
        } catch {
            throw GiftStoreCorrupt(message: "Gift cards failed to encode")
        }
        _ = try decodeGiftCards(data)
        return data
    }

    static func decodeGiftCards(_ data: Data) throws -> [StoredGiftCard] {
        try validateKeySets(
            data,
            keyRules: [
                KeyRule(keys: knownKeys(StoredGiftCard.CodingKeys.self)),
                KeyRule(under: "fundingFailures", keys: knownKeys(GiftFundingFailure.CodingKeys.self))
            ]
        )
        do {
            return try JSONDecoder().decode([StoredGiftCard].self, from: data)
        } catch {
            // Never interpolate the decoder's error: it can quote the blob, and the blob holds
            // bearer mnemonics.
            throw GiftStoreCorrupt(message: "Gift card store failed to decode")
        }
    }

    static func encodeReceivedGifts(_ gifts: [ReceivedGift]) throws -> Data {
        let data: Data
        do {
            data = try JSONEncoder().encode(gifts)
        } catch {
            throw GiftStoreCorrupt(message: "Received gifts failed to encode")
        }
        _ = try decodeReceivedGifts(data)
        return data
    }

    static func decodeReceivedGifts(_ data: Data) throws -> [ReceivedGift] {
        try validateKeySets(
            data,
            keyRules: [
                KeyRule(keys: knownKeys(ReceivedGift.CodingKeys.self)),
                KeyRule(under: "claimLink", keys: knownKeys(GiftLinkPayload.CodingKeys.self))
            ]
        )
        do {
            return try JSONDecoder().decode([ReceivedGift].self, from: data)
        } catch {
            throw GiftStoreCorrupt(message: "Received gift store failed to decode")
        }
    }

    /// Which key set applies to an object: the record itself, or objects found under one of the
    /// record's fields.
    private struct KeyRule {
        let under: String?
        let keys: Set<String>

        init(under: String? = nil, keys: Set<String>) {
            self.under = under
            self.keys = keys
        }
    }

    private static func knownKeys<Key: CodingKey & CaseIterable>(_ type: Key.Type) -> Set<String> {
        Set(type.allCases.map(\.stringValue))
    }

    private static func validateKeySets(_ data: Data, keyRules: [KeyRule]) throws {
        guard let records = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw GiftStoreCorrupt(message: "Gift store blob is not a list")
        }
        guard let recordRule = keyRules.first(where: { $0.under == nil }) else { return }
        for record in records {
            guard let object = record as? [String: Any] else {
                throw GiftStoreCorrupt(message: "Gift store record is not an object")
            }
            try validateKeys(of: object, against: recordRule.keys)
            for rule in keyRules {
                guard let field = rule.under else { continue }
                for nested in nestedObjects(object[field]) {
                    try validateKeys(of: nested, against: rule.keys)
                }
            }
        }
    }

    private static func nestedObjects(_ value: Any?) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            return [object]
        }
        if let list = value as? [Any] {
            return list.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func validateKeys(of object: [String: Any], against known: Set<String>) throws {
        for key in object.keys where !known.contains(key) {
            // Only the key is named — keys are schema, values are custody data.
            throw GiftStoreCorrupt(message: "Gift store record carries unknown field \(key)")
        }
    }
}
