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
        connectionDetails: {
            ZMConnectionDetails(
                online: false,
                peerCount: 0,
                globalConnections: 0,
                pendingQueues: 0,
                pendingMessageCount: 0,
                pendingInvites: 0,
                dhtHealth: "unknown",
                dhtLastCheck: nil,
                consecutiveFailures: 0,
                directConversations: 0,
                groupConversations: 0,
                dhtBootstrapped: false,
                dhtFirewalled: nil,
                dhtRandomized: nil,
                rtNodes: 0,
                relayEnabled: false,
                relaysConnected: 0,
                relaysTotal: 0
            )
        },
        createDirectConversation: { publicKey, displayName in
            ZMConversation(
                id: publicKey,
                type: .direct,
                participantIds: [publicKey],
                displayName: displayName ?? String(publicKey.prefix(8))
            )
        },
        createGroup: { name, participantKeys in
            ZMConversation(id: name, type: .group, participantIds: participantKeys, displayName: name)
        },
        renameGroup: { _, _ in },
        addMember: { _, _, _ in },
        leaveConversation: { _ in },
        removeConversation: { _ in },
        hasLeftDirectConversation: { _ in false },
        messages: { _, _ in [] },
        sendMessage: { conversationId, content, _ in
            ZMMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                senderId: "test",
                content: content,
                isFromMe: true
            )
        },
        sendMedia: { conversationId, _, contentType, caption, _ in
            ZMMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                senderId: "test",
                content: caption,
                contentType: contentType,
                isFromMe: true
            )
        },
        sendWalletAddress: { conversationId, address in
            ZMMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                senderId: "test",
                content: address,
                contentType: ChatContentType.walletAddress,
                isFromMe: true
            )
        },
        markRead: { _ in },
        messageStatusStream: { Empty().eraseToAnyPublisher() },
        mediaProgressStream: { Empty().eraseToAnyPublisher() },
        mediaCompleteStream: { Empty().eraseToAnyPublisher() },
        setReadReceiptsEnabled: { _ in },
        setPresenceVisible: { _ in },
        messageReceivedStream: { Empty().eraseToAnyPublisher() },
        setActiveConversation: { _ in },
        setBlockedKeys: { _ in }
    )
}
