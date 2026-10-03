//
//  ChatContactsListParityTests.swift
//  zodlTests
//
//  The contacts list against Android's `ChatContactsView`: A–Z sections, and a Start-chat
//  action that opens (or re-opens) the DM, offered only for contacts who are not blocked.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite(.serialized) struct ChatContactsListParityTests {
    private func key(_ character: Character) -> String {
        String(repeating: character, count: PublicKeyRules.hexLength)
    }

    @MainActor @Test func contactsAreGroupedUnderTheirFirstLetter() {
        withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            var state = ChatContactsList.State()
            state.$chatContacts.withLock {
                $0 = ChatContacts(
                    lastUpdated: .distantPast,
                    version: ChatContacts.Constants.version,
                    contacts: [
                        ChatContact(publicKey: key("a"), name: "bob", isSaved: true),
                        ChatContact(publicKey: key("b"), name: "Alice", isSaved: true),
                        ChatContact(publicKey: key("c"), name: "Ben", isSaved: true),
                        // Block-only rows are not contacts and never form a section.
                        ChatContact(publicKey: key("d"), name: "Zed", isBlocked: true, isSaved: false)
                    ]
                )
            }

            #expect(state.sections.map(\.letter) == ["A", "B"])
            #expect(state.sections.last?.contacts.map(\.name) == ["Ben", "bob"])
        }
    }

    @MainActor @Test func startChatOpensTheDirectConversationForThatKey() async {
        let contact = ChatContact(publicKey: key("a"), name: "Ada", isSaved: true)
        let conversation = ZMConversation(id: "dm", type: .direct, participantIds: [contact.publicKey], displayName: nil)
        let requested = LockIsolated<String?>(nil)
        let store = TestStore(initialState: ChatContactsList.State()) {
            ChatContactsList()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
            $0.zappMessaging.createDirectConversation = { publicKey, _ in
                requested.setValue(publicKey)
                return conversation
            }
        }

        await store.send(.startChatTapped(contact)) {
            $0.isStartingChat = true
        }
        await store.receive(.conversationOpened(conversation)) {
            $0.isStartingChat = false
        }
        #expect(requested.value == contact.publicKey)
    }

    @MainActor @Test func aBlockedContactCannotStartAChat() async {
        let contact = ChatContact(publicKey: key("a"), name: "Ada", isBlocked: true, isSaved: true)
        let store = TestStore(initialState: ChatContactsList.State()) {
            ChatContactsList()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
        }

        await store.send(.startChatTapped(contact))
    }

    @MainActor @Test func aFailedStartReleasesTheButton() async {
        let contact = ChatContact(publicKey: key("a"), name: "Ada", isSaved: true)
        let store = TestStore(initialState: ChatContactsList.State()) {
            ChatContactsList()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
            $0.zappMessaging.createDirectConversation = { _, _ in throw ZappMessagingAppError.ownPublicKey }
        }

        await store.send(.startChatTapped(contact)) {
            $0.isStartingChat = true
        }
        await store.receive(.startChatFailed) {
            $0.isStartingChat = false
        }
    }
}
