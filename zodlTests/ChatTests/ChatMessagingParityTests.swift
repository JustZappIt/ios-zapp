//
//  ChatMessagingParityTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
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
            $0.errorCode = "OWN_PUBLIC_KEY"
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

    @MainActor @Test func failedTextSendRemainsVisibleAndRestoresDraft() async {
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
        #expect(store.state.draft == "do not lose this")
        #expect(store.state.sendDidFail)
        #expect(store.state.sendFailureMessage == "Transport unavailable")
    }
}
