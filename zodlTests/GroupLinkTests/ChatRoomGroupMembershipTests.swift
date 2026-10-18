// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ChatRoomGroupMembershipTests {
    private static let group = ZMConversation(
        id: "room", type: .group, participantIds: ["owner", "guest"], displayName: "Hiking Crew"
    )

    @MainActor
    @Test func openGroupLoadsMetadataWithoutTheChatsScreen() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .groupInvite
            state.groupInviteState.stage = .joined(conversationId: "room", nameHint: "Hiking Crew", alreadyMember: false)
            let conversations = CurrentValueSubject<[ZMConversation], Never>([Self.group])
            let store = TestStore(initialState: state) { Root() } withDependencies: {
                $0.walletStorage = .noOp
                $0.mainQueue = .immediate
                $0.zappMessaging.conversationsStream = { conversations.eraseToAnyPublisher() }
                $0.klipyGIF.isConfigured = { false }
            }
            store.exhaustivity = .off

            await store.send(.groupInvite(.delegate(.openConversation("room"))))
            await store.receive {
                guard case .destination(.updateDestination) = $0 else { return false }
                return true
            }
            await store.receive(\.chatNotificationTapped)
            #expect(store.state.path == .chatRoom)
            #expect(store.state.chatsListState.conversations.isEmpty)

            await store.send(.chatRoom(.onAppear))
            await store.receive(\.chatRoom.conversationChanged)
            #expect(store.state.chatRoomState.conversation == Self.group)
            #expect(store.state.chatRoomState.title == "Hiking Crew")
            #expect(store.state.chatRoomState.isGroup)
            await store.send(.chatRoom(.titleTapped))
            #expect(store.state.path == .groupInfo)
            #expect(store.state.groupInfoState.conversation == Self.group)
            await store.send(.chatRoom(.onDisappear))
            await store.finish()
        }
    }

    @MainActor
    @Test func removalWhileTheRoomIsOpenPreventsSendingAndPreservesHistory() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let conversations = CurrentValueSubject<[ZMConversation], Never>([Self.group])
            let cancelled = SignalledRecords<Void>()
            let sends = SignalledRecords<String>()
            let historyGate = ResumableGate()
            let history = ZMMessage(
                id: "old", conversationId: "room", senderId: "owner", content: "Keep this history", isFromMe: false
            )
            let store = TestStore(initialState: ChatRoom.State(conversationId: "room")) { ChatRoom() } withDependencies: {
                $0.mainQueue = .immediate
                $0.zappMessaging.conversationsStream = {
                    conversations.handleEvents(receiveCancel: { cancelled.recordCall() }).eraseToAnyPublisher()
                }
                $0.zappMessaging.messages = { _, _ in
                    await historyGate.wait()
                    return [history]
                }
                $0.zappMessaging.sendMessage = { id, content, _ in
                    sends.record(content)
                    return ZMMessage(id: "new", conversationId: id, senderId: "guest", content: content, isFromMe: true)
                }
                $0.klipyGIF.isConfigured = { false }
            }
            store.exhaustivity = .off
            await store.send(.onAppear)
            await store.receive(\.conversationChanged)
            historyGate.open()
            await store.receive(\.messagesLoaded)
            #expect(!store.state.isRemovedFromGroup)
            await store.send(.draftChanged("Unsent draft"))

            let removed = ZMConversation(
                id: "room",
                type: .group,
                participantIds: ["owner", "guest"],
                displayName: "Hiking Crew",
                removedAt: Date(timeIntervalSince1970: 1_000)
            )
            conversations.send([removed])
            await store.receive(\.conversationChanged)
            #expect(store.state.isRemovedFromGroup)
            await store.send(.sendTapped)
            #expect(store.state.draft == "Unsent draft")
            #expect(store.state.messages == [history])
            #expect(sends.isEmpty)

            await store.send(.onDisappear)
            await cancelled.countReached(1)
            conversations.send([Self.group])
            await store.finish()
            #expect(store.state.isRemovedFromGroup, "the conversation subscription must stop with the room")
        }
    }
}
