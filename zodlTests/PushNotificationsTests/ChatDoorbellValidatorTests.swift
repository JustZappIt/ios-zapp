//
//  ChatDoorbellValidatorTests.swift
//  zodlTests
//

import Foundation
import Testing
@testable import zodl_internal

@Suite struct ChatDoorbellValidatorTests {
    @Test func acceptsExpectedContentlessBlindPushEnvelope() {
        #expect(ChatDoorbellValidator.validate(userInfo: validUserInfo(), expectedSenderId: senderId) != nil)
    }

    @Test func acceptsCompactEncodedPayloadLengthAboveInlineRange() {
        #expect(ChatDoorbellValidator.validate(
            userInfo: validUserInfo(encryptedPayloadLength: 300),
            expectedSenderId: senderId
        ) != nil)
    }

    @Test func malformedAndOversizedPayloadsAreIgnored() {
        var malformed = validUserInfo()
        malformed["payload"] = "not-base64"
        #expect(ChatDoorbellValidator.validate(userInfo: malformed, expectedSenderId: senderId) == nil)

        var oversized = validUserInfo()
        oversized["padding"] = String(repeating: "x", count: 4_096)
        #expect(ChatDoorbellValidator.validate(userInfo: oversized, expectedSenderId: senderId) == nil)
    }

    @Test func dynamicAlertTextIsRejected() {
        var info = validUserInfo()
        var aps = info["aps"] as! [String: Any]
        aps["alert"] = ["title": "A contact", "body": "plaintext message"]
        info["aps"] = aps
        #expect(ChatDoorbellValidator.validate(userInfo: info, expectedSenderId: senderId) == nil)
    }

    @Test func unknownValidTopicsRouteSafelyToChats() {
        #expect(ChatDoorbellDecider.destination(binding: nil, blockedWriters: []) == .chats)
        #expect(ChatDoorbellDecider.shouldPresent(
            binding: nil,
            blockedWriters: [],
            activeConversationId: nil,
            isForeground: false,
            deliveryEnabled: true
        ))
    }

    @Test func activeConversationForegroundDeliveryIsSuppressed() {
        #expect(!ChatDoorbellDecider.shouldPresent(
            binding: binding,
            blockedWriters: [],
            activeConversationId: binding.conversationId,
            isForeground: true,
            deliveryEnabled: true
        ))
    }

    @Test func blockedWriterSuppressesAlertAndRoutesToChats() {
        #expect(!ChatDoorbellDecider.shouldPresent(
            binding: binding,
            blockedWriters: [binding.writerPublicKey],
            activeConversationId: nil,
            isForeground: false,
            deliveryEnabled: true
        ))
        #expect(ChatDoorbellDecider.destination(
            binding: binding,
            blockedWriters: [binding.writerPublicKey]
        ) == .chats)
    }

    @Test func knownTapRoutesToConversation() {
        #expect(ChatDoorbellDecider.destination(binding: binding, blockedWriters: []) == .conversation("chat-1"))
    }
}

private extension ChatDoorbellValidatorTests {
    var senderId: String { "123456789" }
    var discoveryKey: Data { Data(repeating: 0xab, count: 32) }
    var topic: String { discoveryKey.map { String(format: "%02x", $0) }.joined() }
    var binding: PushTopicBinding {
        PushTopicBinding(topic: topic, conversationId: "chat-1", writerPublicKey: "cafe")
    }

    func validUserInfo(encryptedPayloadLength: Int = 48) -> [AnyHashable: Any] {
        var encoded = Data([3])
        if encryptedPayloadLength <= 0xfc {
            encoded.append(UInt8(encryptedPayloadLength))
        } else {
            encoded.append(0xfd)
            encoded.append(UInt8(encryptedPayloadLength & 0xff))
            encoded.append(UInt8((encryptedPayloadLength >> 8) & 0xff))
        }
        encoded.append(Data(repeating: 7, count: encryptedPayloadLength))
        encoded.append(32)
        encoded.append(discoveryKey)

        return [
            "google.c.sender.id": senderId,
            "from": "/topics/\(topic)",
            "payload": encoded.base64EncodedString(),
            "aps": [
                "alert": [
                    "title": ChatDoorbellValidator.genericTitle,
                    "body": ChatDoorbellValidator.genericBody
                ],
                "category": "room_message",
                "mutable-content": 1,
                "sound": "default",
                "thread-id": discoveryKey.base64EncodedString()
            ]
        ]
    }
}
