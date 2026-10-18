//
//  ChatSendZecAddressRequestTests.swift
//  zodlTests
//
//  Send ZEC from a chat: where the recipient's address comes from, and what a direct chat does
//  when it has none (Android's `onSendZecClick` and `addressRequestSheet`).
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Serialized: drives Root and ChatRoom state that share process-global `@Shared` stores.
@Suite(.serialized) @MainActor struct ChatSendZecAddressRequestTests {
    private static let requesterAddress = "tmP3uLtGx5GPddkq8a6ddmXhqJJ3vy6tpTE"

    private func conversation(_ type: ConversationType) -> ZMConversation {
        ZMConversation(id: "conversation", type: type, participantIds: ["peerkey"], displayName: "Dee")
    }

    private func requestFromPeer() -> ZMMessage {
        ZMMessage(
            id: "request-1",
            conversationId: "conversation",
            senderId: "peerkey",
            content: ChatPaymentRequest.json(
                id: "r1",
                amount: 1,
                requesterAddress: Self.requesterAddress,
                memo: nil
            ) ?? "",
            contentType: ChatContentType.paymentRequest,
            timestamp: Date(timeIntervalSince1970: 100),
            isFromMe: false
        )
    }

    private func roomState(_ type: ConversationType, messages: [ZMMessage] = []) -> ChatRoom.State {
        var state = ChatRoom.State(conversationId: "conversation")
        state.conversation = conversation(type)
        state.messages = messages
        state.$chatContacts.withLock { $0 = .empty }
        return state
    }

    // MARK: - Where the address comes from

    @Test func aRequestThePeerSentPrefillsSendInADirectChat() {
        let state = roomState(.direct, messages: [requestFromPeer()])

        #expect(state.resolvedPeerWalletAddress == Self.requesterAddress)
        #expect(!state.needsPeerAddressRequest)
    }

    /// In a group a request doesn't name one recipient plainly enough to prefill.
    @Test func aRequestInAGroupDoesNotPrefillSend() {
        let state = roomState(.group, messages: [requestFromPeer()])

        #expect(state.resolvedPeerWalletAddress == nil)
        #expect(!state.needsPeerAddressRequest)
    }

    // MARK: - No address in a direct chat

    @Test func aDirectChatWithNoAddressAsksBeforeOpeningSend() async {
        let store = TestStore(initialState: roomState(.direct)) { ChatRoom() }
        store.exhaustivity = .off

        // Parked until the attachment sheet has finished closing: iOS can't present over it.
        await store.send(.sendZecTapped) {
            $0.pendingAttachment = .addressRequest
        }
        await store.send(.attachmentSheetClosed) {
            $0.pendingAttachment = nil
            $0.addressRequest = ChatRoom.AddressRequestPrompt(name: "Dee")
        }
    }

    /// Android wraps a shared address as `{"content": addr}`. Send ZEC prefills the address the
    /// bubble shows, not the wrapper, and so doesn't ask for one it already has.
    @Test func aWrappedSharedAddressIsUnwrapped() {
        var state = roomState(.direct)
        state.messages = [
            ZMMessage(
                id: "addr",
                conversationId: "conversation",
                senderId: "peer",
                content: #"{"content":"u1peeraddress"}"#,
                contentType: ChatContentType.walletAddress,
                isFromMe: false
            )
        ]

        #expect(state.resolvedPeerWalletAddress == "u1peeraddress")
        #expect(!state.needsPeerAddressRequest)
    }

    /// The canned request doesn't clear the reply a composer send is still holding.
    @Test func askingLeavesAComposerSendsReplyAlone() async {
        var state = roomState(.direct)
        let quoted = ZMMessage(id: "q", conversationId: "conversation", senderId: "peer", content: "hi", isFromMe: false)
        state.pendingReply = quoted
        state.pendingReplyClientId = "local_composer"
        state.addressRequest = ChatRoom.AddressRequestPrompt(name: "Dee")

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { conversationId, content, _ in
                ZMMessage(id: "sent-1", conversationId: conversationId, senderId: "me", content: content, isFromMe: true)
            }
        }
        store.exhaustivity = .off

        await store.send(.addressRequest(.askForAddressTapped))
        await store.receive(\.sendSucceeded)

        #expect(store.state.pendingReply == quoted)
        #expect(store.state.pendingReplyClientId == "local_composer")
    }

    @Test func askingPostsTheRequestMessageAndLeavesTheDraftAlone() async {
        var state = roomState(.direct)
        state.draft = "half-typed"
        state.addressRequest = ChatRoom.AddressRequestPrompt(name: "Dee")
        let sent = LockIsolated<[String]>([])

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { conversationId, content, _ in
                sent.withValue { $0.append(content) }
                return ZMMessage(
                    id: "sent-1",
                    conversationId: conversationId,
                    senderId: "me",
                    content: content,
                    contentType: ChatContentType.text,
                    isFromMe: true
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.addressRequest(.askForAddressTapped)) {
            $0.addressRequest = nil
        }
        await store.receive(\.sendSucceeded)

        #expect(sent.value == [String(localizable: .chatRoomSendZecAddressRequestText)])
        #expect(store.state.draft == "half-typed")
    }

    // MARK: - Root routing

    private func rootStore(_ room: ChatRoom.State) -> StoreOf<Root> {
        var state = Root.State.initial
        state.chatRoomState = room
        state.path = .chatRoom

        return Store(initialState: state) {
            Root()
        } withDependencies: {
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.mnemonic = .mock
            $0.sdkSynchronizer = .noOp
            $0.walletStorage = .noOp
            $0.zcashSDKEnvironment = .testnet
        }
    }

    @Test func rootWaitsWhileTheRoomAsksForAnAddress() {
        let store = rootStore(roomState(.direct))

        store.send(.chatRoom(.sendZecTapped))

        #expect(store.path == .chatRoom)
        #expect(store.chatRoomState.pendingAttachment == .addressRequest)
    }

    @Test func enterAnAddressOpensTheEmptyFormInChatContext() {
        var room = roomState(.direct)
        room.addressRequest = ChatRoom.AddressRequestPrompt(name: "Dee")
        let store = rootStore(room)

        store.send(.chatRoom(.addressRequest(.enterAddressTapped)))

        #expect(store.path == .sendCoordFlow)
        #expect(store.returnsToChatRoomAfterWalletFlow)
        #expect(store.chatSendContext?.conversationId == "conversation")
        #expect(store.sendCoordFlowState.sendFormState.address.data.isEmpty)
    }
}
