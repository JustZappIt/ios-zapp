//
//  ChatMessagingParityTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite struct ChatMessagingParityTests {
    private struct SendFailure: LocalizedError {
        var errorDescription: String? { "Transport unavailable" }
    }

    @MainActor @Test func ownPublicKeyCannotStartDirectChat() async {
        let ownKey = String(repeating: "a", count: PublicKeyRules.hexLength)
        var state = NewChat.State()
        state.myPublicKey = ownKey

        let store = TestStore(initialState: state) {
            NewChat()
        }

        await store.send(.peerKeyChanged("0x\(ownKey)")) {
            $0.searchInput = "0x\(ownKey)"
            $0.errorCode = .ownPublicKey
        }

        #expect(store.state.isOwnKey)
        #expect(!store.state.canStart)

        await store.send(.startTapped)
        #expect(!store.state.isCreating)
    }

    @MainActor @Test func textSendAppearsImmediatelyThenReconcilesWithPersistedMessage() async {
        let persisted = ZMMessage(
            id: "persisted-message",
            conversationId: "conversation",
            senderId: "me",
            content: "hello",
            isFromMe: true,
            status: "queued"
        )
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { _, _, _ in persisted }
        }
        store.exhaustivity = .off

        await store.send(.draftChanged("hello"))
        await store.send(.sendTapped)

        #expect(store.state.draft.isEmpty)
        #expect(store.state.messages.count == 1)
        #expect(store.state.messages.first?.status == "sending")

        await store.receive(\.sendSucceeded)

        #expect(store.state.messages == [persisted])
        #expect(!store.state.sendDidFail)
    }

    @MainActor @Test func failedTextSendRemainsVisibleForRetryWithoutOverwritingTheComposer() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { _, _, _ in throw SendFailure() }
        }
        store.exhaustivity = .off

        await store.send(.draftChanged("do not lose this"))
        await store.send(.sendTapped)

        #expect(store.state.messages.first?.status == "sending")

        await store.receive(\.sendFailed)

        #expect(store.state.messages.first?.status == "failed")
        #expect(store.state.draft.isEmpty)
        #expect(store.state.sendDidFail)
        #expect(store.state.sendFailureMessage == String(localizable: .chatRoomSendFailed))
    }

    @Test func persistedEchoBeforeSendResponseDoesNotDuplicateOrMisorderMessages() {
        let optimistic = ZMMessage(
            id: "local-message",
            conversationId: "conversation",
            senderId: "me",
            content: "hello",
            timestamp: Date(timeIntervalSince1970: 30),
            isFromMe: true,
            status: "sending"
        )
        let persisted = ZMMessage(
            id: "persisted-message",
            conversationId: "conversation",
            senderId: "me",
            content: "hello",
            timestamp: Date(timeIntervalSince1970: 10),
            isFromMe: true,
            status: "queued"
        )
        let later = ZMMessage(
            id: "later-message",
            conversationId: "conversation",
            senderId: "peer",
            content: "later",
            timestamp: Date(timeIntervalSince1970: 20),
            isFromMe: false
        )
        var state = ChatRoom.State(conversationId: "conversation")
        state.insert(optimistic)
        state.insert(persisted)
        state.insert(later)

        state.reconcile(clientId: optimistic.id, with: persisted)

        #expect(state.messages.map(\.id) == [persisted.id, later.id])
    }

    @Test func deliveryStatusParsingMatchesTheSDKContract() {
        typealias Status = ChatMessageStatusIndicator.Status

        #expect(Status(wire: "sending") == .sending)
        #expect(Status(wire: "queued") == .queued)
        #expect(Status(wire: "sent") == .sent)
        #expect(Status(wire: "delivered") == .delivered)
        #expect(Status(wire: "read") == .read)
        #expect(Status(wire: "failed") == .failed)
        #expect(Status(wire: nil) == .sent)
        #expect(Status(wire: "legacy") == .sent)
        #expect(Status.exact(wire: "legacy") == nil)
    }

    @Test func deliveryStatusAdvancesMonotonically() {
        #expect(ChatMessageStatusOrder.advance(from: "sending", to: "queued") == "queued")
        #expect(ChatMessageStatusOrder.advance(from: "queued", to: "sent") == "sent")
        #expect(ChatMessageStatusOrder.advance(from: "sent", to: "delivered") == "delivered")
        #expect(ChatMessageStatusOrder.advance(from: "delivered", to: "read") == "read")

        #expect(ChatMessageStatusOrder.advance(from: "sent", to: "queued") == "sent")
        #expect(ChatMessageStatusOrder.advance(from: "delivered", to: "sent") == "delivered")
        #expect(ChatMessageStatusOrder.advance(from: "read", to: "delivered") == "read")
        #expect(ChatMessageStatusOrder.advance(from: "delivered", to: "unknown") == "delivered")
    }

    @MainActor @Test func deliveryIndicatorDistinguishesRelayDeliveryAndRead() {
        let queued = ChatMessageStatusIndicator(status: .queued, mutedColor: .gray, readColor: .blue)
        let sent = ChatMessageStatusIndicator(status: .sent, mutedColor: .gray, readColor: .blue)
        let delivered = ChatMessageStatusIndicator(status: .delivered, mutedColor: .gray, readColor: .blue)
        let read = ChatMessageStatusIndicator(status: .read, mutedColor: .gray, readColor: .blue)

        #expect(queued.text == "◷")
        #expect(queued.status.tickCount == 1)
        #expect(sent.text == "✓")
        #expect(sent.status.tickCount == 1)
        #expect(delivered.text == "✓")
        #expect(delivered.status.tickCount == 2)
        #expect(!delivered.status.usesHighlightedColor)
        #expect(read.status.tickCount == 3)
        #expect(read.status.usesHighlightedColor)
        #expect(delivered.accessibilityLabel == String(localizable: .chatRoomStatusDelivered))
        #expect(sent.accessibilityLabel == String(localizable: .chatRoomStatusSent))
    }

    @Test func disablingReadReceiptsDowngradesVisibleReadToDelivered() {
        let status = ChatMessageStatusIndicator.Status.read

        #expect(status.visible(readReceiptsEnabled: true) == .read)
        #expect(status.visible(readReceiptsEnabled: false) == .delivered)
        #expect(ChatMessageStatusIndicator.Status.sent.visible(readReceiptsEnabled: false) == .sent)
    }

    @MainActor @Test func messageReloadDoesNotDowngradeANewerVisibleStatus() async {
        let delivered = ZMMessage(
            id: "message",
            conversationId: "conversation",
            senderId: "me",
            content: "hello",
            isFromMe: true,
            status: "delivered"
        )
        let staleReload = delivered.withStatus("sent")
        var state = ChatRoom.State(conversationId: "conversation")
        state.messages = [delivered]
        let store = TestStore(initialState: state) {
            ChatRoom()
        }

        await store.send(.messagesLoaded([staleReload])) {
            $0.isLoading = false
            $0.messages = [delivered]
        }
    }

    @Test func earlyStatusesRemainMonotonicUntilTheMessageLoads() {
        var state = ChatRoom.State(conversationId: "conversation")
        state.rememberEarlyStatus("message", "delivered")
        state.rememberEarlyStatus("message", "sent")
        state.insert(
            ZMMessage(
                id: "message",
                conversationId: "conversation",
                senderId: "me",
                content: "hello",
                isFromMe: true,
                status: "queued"
            )
        )

        #expect(state.messages.first?.status == "delivered")
        #expect(state.earlyStatuses.isEmpty)
    }

    @MainActor @Test func tappingFailedMessageRetriesAndReconcilesIt() async {
        let failed = ZMMessage(
            id: "local-message",
            conversationId: "conversation",
            senderId: "me",
            content: "retry me",
            isFromMe: true,
            status: "failed"
        )
        let persisted = ZMMessage(
            id: "persisted-message",
            conversationId: "conversation",
            senderId: "me",
            content: "retry me",
            isFromMe: true,
            status: "queued"
        )
        var state = ChatRoom.State(conversationId: "conversation")
        state.insert(failed)
        state.sendDidFail = true
        state.sendFailureMessage = String(localizable: .chatRoomSendFailed)

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { _, _, _ in persisted }
        }
        store.exhaustivity = .off

        await store.send(.retrySendTapped(failed))
        #expect(store.state.messages.first?.status == "sending")
        #expect(!store.state.sendDidFail)

        await store.receive(\.sendSucceeded)
        #expect(store.state.messages == [persisted])
    }

    @Test func successfulRefreshClearsRelatedFailuresWithoutHidingPostCreateWarnings() {
        let refresh = ZappMessagingOperation.local(.conversationRefresh)
        let postEventFailure = ZappMessagingOperation.sdk(.conversationRefresh(.messageReceived))
        let create = ZappMessagingOperation.local(.conversationCreate)
        let postCreateConnectionFailure = ZappMessagingOperation.sdk(.conversationConnect)

        #expect(refresh.recovers(postEventFailure))
        #expect(!create.recovers(postCreateConnectionFailure))
    }
}
