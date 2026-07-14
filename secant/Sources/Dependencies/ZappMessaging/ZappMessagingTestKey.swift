//
//  ZappMessagingTestKey.swift
//  Zapp
//

import Combine
import ComposableArchitecture
import Foundation
import ZappMessaging

extension ZappMessagingClient: TestDependencyKey {
    /// Inert by default: a test that does not care about chat must not boot a
    /// Bare worklet. Tests that do care override the closures they need.
    static let testValue = ZappMessagingClient(
        start: { },
        suspend: { },
        resume: { },
        wipe: { },
        setDisplayName: { _ in },
        retryIdentityDerivation: { },
        updateDisplayName: { _ in },
        stateStream: { Empty().eraseToAnyPublisher() },
        latestState: { ZappMessagingState() },
        conversationsStream: { Empty().eraseToAnyPublisher() },
        refreshConversations: { },
        createDirectConversation: { publicKey, displayName in
            ZMConversation(
                id: publicKey,
                type: .direct,
                participantIds: [publicKey],
                displayName: displayName ?? String(publicKey.prefix(8))
            )
        },
        messages: { _, _ in [] },
        sendMessage: { conversationId, content in
            ZMMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                senderId: "test",
                content: content,
                isFromMe: true
            )
        },
        markRead: { _ in },
        messageReceivedStream: { Empty().eraseToAnyPublisher() },
        setActiveConversation: { _ in }
    )
}
