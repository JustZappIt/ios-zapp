//
//  ChatDoorbellValidator.swift
//  Zapp
//

import Foundation

struct ValidatedChatDoorbell: Equatable, Sendable {
    var topic: String
}

/// Validates only the contentless blind-push v3 envelope. It never decodes or
/// decrypts message content and never derives a topic in Swift.
enum ChatDoorbellValidator {
    static let genericTitle = "Zapp"
    static let genericBody = "New private message"

    static func validate(
        userInfo: [AnyHashable: Any],
        expectedSenderId: String?
    ) -> ValidatedChatDoorbell? {
        guard let expectedSenderId, !expectedSenderId.isEmpty,
              let senderId = userInfo["google.c.sender.id"] as? String,
              senderId == expectedSenderId,
              let from = userInfo["from"] as? String,
              from.hasPrefix(topicPrefix) else {
            return nil
        }

        let topic = String(from.dropFirst(topicPrefix.count))
        guard topic.range(of: topicPattern, options: .regularExpression) != nil,
              let payload = userInfo["payload"] as? String,
              payload.count >= minimumBase64Length,
              payload.count <= maximumBase64Length,
              payload.count.isMultiple(of: base64Quantum),
              let rawPayload = Data(base64Encoded: payload),
              validateBlindPush(rawPayload, topic: topic),
              validateAPS(userInfo["aps"], topic: topic),
              serializedSize(userInfo) <= maximumEnvelopeSize else {
            return nil
        }

        return ValidatedChatDoorbell(topic: topic)
    }

    private static func validateAPS(_ rawAPS: Any?, topic: String) -> Bool {
        guard let aps = rawAPS as? [String: Any],
              Set(aps.keys) == expectedAPSKeys,
              aps["category"] as? String == "room_message",
              aps["sound"] as? String == "default",
              (aps["mutable-content"] as? NSNumber)?.intValue == 1,
              let alert = aps["alert"] as? [String: Any],
              Set(alert.keys) == expectedAlertKeys,
              alert["title"] as? String == genericTitle,
              alert["body"] as? String == genericBody,
              let threadId = aps["thread-id"] as? String,
              let threadData = Data(base64Encoded: threadId),
              threadData.hexString == topic else {
            return false
        }

        return true
    }

    private static func validateBlindPush(_ data: Data, topic: String) -> Bool {
        var cursor = 0

        guard readCompactUInt(data, cursor: &cursor) == expectedBlindPushVersion,
              let encryptedLength = readCompactUInt(data, cursor: &cursor),
              encryptedLength >= minimumEncryptedPayloadLength,
              encryptedLength <= maximumEncryptedPayloadLength,
              cursor + encryptedLength <= data.count else {
            return false
        }
        cursor += encryptedLength

        guard readCompactUInt(data, cursor: &cursor) == discoveryKeyLength,
              cursor + discoveryKeyLength == data.count else {
            return false
        }

        return data[cursor..<(cursor + discoveryKeyLength)].hexString == topic
    }

    private static func readCompactUInt(_ data: Data, cursor: inout Int) -> Int? {
        guard cursor < data.count else { return nil }
        let marker = Int(data[cursor])
        cursor += 1

        switch marker {
        case 0...0xfc:
            return marker
        case 0xfd:
            return readLittleEndian(data, cursor: &cursor, byteCount: 2)
        case 0xfe:
            return readLittleEndian(data, cursor: &cursor, byteCount: 4)
        default:
            return readLittleEndian(data, cursor: &cursor, byteCount: 8)
        }
    }

    private static func readLittleEndian(
        _ data: Data,
        cursor: inout Int,
        byteCount: Int
    ) -> Int? {
        guard byteCount <= MemoryLayout<Int>.size,
              cursor + byteCount <= data.count else { return nil }
        var value: UInt64 = 0
        for shift in 0..<byteCount {
            value |= UInt64(data[cursor + shift]) << (shift * 8)
        }
        cursor += byteCount
        guard value <= UInt64(Int.max) else { return nil }
        return Int(value)
    }

    private static func serializedSize(_ userInfo: [AnyHashable: Any]) -> Int {
        let stringKeyed = Dictionary(uniqueKeysWithValues: userInfo.compactMap { key, value in
            (key as? String).map { ($0, value) }
        })
        guard stringKeyed.count == userInfo.count,
              JSONSerialization.isValidJSONObject(stringKeyed),
              let data = try? JSONSerialization.data(withJSONObject: stringKeyed) else {
            return .max
        }
        return data.count
    }

    private static let topicPrefix = "/topics/"
    private static let topicPattern = "^[0-9a-f]{64}$"
    private static let expectedAPSKeys = Set(["alert", "category", "mutable-content", "sound", "thread-id"])
    private static let expectedAlertKeys = Set(["body", "title"])
    private static let expectedBlindPushVersion = 3
    private static let discoveryKeyLength = 32
    private static let minimumEncryptedPayloadLength = 40
    private static let maximumEncryptedPayloadLength = 1_470
    private static let minimumBase64Length = 32
    private static let maximumBase64Length = 1_960
    private static let maximumEnvelopeSize = 4_096
    private static let base64Quantum = 4
}

enum ChatDoorbellDecider {
    static func shouldPresent(
        binding: PushTopicBinding?,
        blockedWriters: Set<String>,
        activeConversationId: String?,
        isForeground: Bool,
        deliveryEnabled: Bool
    ) -> Bool {
        guard deliveryEnabled else { return false }
        guard let binding else { return true }

        let writer = normalize(binding.writerPublicKey)
        let blocked = blockedWriters.map(normalize).contains(writer)
        let isActive = isForeground && activeConversationId == binding.conversationId
        return !writer.isEmpty && !blocked && !isActive
    }

    static func destination(
        binding: PushTopicBinding?,
        blockedWriters: Set<String>
    ) -> PushNotificationDestination {
        guard let binding,
              !blockedWriters.map(normalize).contains(normalize(binding.writerPublicKey)) else {
            return .chats
        }
        return .conversation(binding.conversationId)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "0x", with: "", options: .anchored)
    }
}

private extension DataProtocol {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
