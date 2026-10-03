//
//  ChatContactsParityRoundTests.swift
//  zodlTests
//
//  The contacts list against Android's `ChatContactsView`: A–Z sections, and a Start-chat
//  action that opens (or re-opens) the DM, offered only for contacts who are not blocked.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@preconcurrency import ZcashLightClientKit
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

/// The add/edit form against Android's `EditChatContactVM`: delete confirms inline, failures are
/// shown rather than only logged, and an edit has to change something before it can be saved.
@Suite(.serialized) struct ChatContactFormRoundTests {
    private struct Failure: Error { }

    private let peerKey = String(repeating: "a", count: PublicKeyRules.hexLength)

    private func account() -> WalletAccount {
        WalletAccount(Account(
            id: AccountUUID(id: [UInt8](repeating: 0x03, count: 16)),
            name: "Zashi",
            keySource: nil,
            seedFingerprint: [UInt8](repeating: 0x04, count: 32),
            hdAccountIndex: Zip32AccountIndex(0),
            ufvk: nil,
            uivk: nil
        ))
    }

    /// The shared account has to exist in the same storage the store reads.
    @MainActor private func editStore(
        _ contact: ChatContact,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ChatContactForm> {
        let storage = InMemoryStorage()
        let state = withDependencies {
            $0.defaultInMemoryStorage = storage
        } operation: {
            let state = ChatContactForm.State(existing: contact)
            state.$zashiWalletAccount.withLock { $0 = account() }
            return state
        }
        return TestStore(initialState: state) {
            ChatContactForm()
        } withDependencies: {
            $0.defaultInMemoryStorage = storage
            configure(&$0)
        }
    }

    @MainActor @Test func anEditCannotBeSavedUntilSomethingChanged() async {
        let store = editStore(ChatContact(publicKey: peerKey, name: "Ada"))

        #expect(!store.state.canSave)

        await store.send(.nameChanged("Ada L")) {
            $0.name = "Ada L"
        }
        #expect(store.state.canSave)

        await store.send(.nameChanged("Ada")) {
            $0.name = "Ada"
        }
        #expect(!store.state.canSave)
    }

    /// A peer opened from their conversation is not a contact yet; saving is what makes it one.
    @Test func anUnsavedPeerCanBeSavedAsItStands() {
        let state = ChatContactForm.State(prefill: ChatContact(publicKey: peerKey, name: "Peer", isSaved: false))

        #expect(state.canSave)
    }

    @MainActor @Test func deleteAsksInlineBeforeItWrites() async {
        let deletes = LockIsolated(0)
        let store = editStore(ChatContact(publicKey: peerKey, name: "Ada")) {
            $0.chatContacts.delete = { _, _ in
                deletes.withValue { $0 += 1 }
                return .empty
            }
        }

        await store.send(.deleteTapped) {
            $0.isConfirmingDelete = true
        }
        await store.send(.deleteCancelled) {
            $0.isConfirmingDelete = false
        }
        #expect(deletes.value == 0)

        await store.send(.deleteTapped) {
            $0.isConfirmingDelete = true
        }
        await store.send(.deleteConfirmed)
        await store.receive(.delegate(.contactsChanged(.empty)))
        #expect(deletes.value == 1)
    }

    @MainActor @Test func aFailedDeleteClosesTheConfirmationAndSaysSo() async {
        let store = editStore(ChatContact(publicKey: peerKey, name: "Ada")) {
            $0.chatContacts.delete = { _, _ in throw Failure() }
        }

        await store.send(.deleteTapped) {
            $0.isConfirmingDelete = true
        }
        await store.send(.deleteConfirmed) {
            $0.isConfirmingDelete = false
            $0.errorMessage = String(localizable: .chatContactsDeleteFailed)
        }
    }

    @MainActor @Test func aFailedSaveIsShownAndClearedByTheNextEdit() async {
        let store = editStore(ChatContact(publicKey: peerKey, name: "Ada")) {
            $0.chatContacts.save = { _, _ in throw Failure() }
        }

        await store.send(.nameChanged("Ada L")) {
            $0.name = "Ada L"
        }
        await store.send(.saveTapped) {
            $0.errorMessage = String(localizable: .chatContactsSaveFailed)
        }
        await store.send(.nameChanged("Ada Lo")) {
            $0.name = "Ada Lo"
            $0.errorMessage = nil
        }
    }

    @MainActor @Test func aFailedBlockKeepsTheDialogUp() async {
        let store = editStore(ChatContact(publicKey: peerKey, name: "Ada")) {
            $0.chatContacts.setBlocked = { _, _, _, _ in throw Failure() }
        }
        store.exhaustivity = .off

        await store.send(.blockTapped)
        await store.send(.alert(.presented(.blockConfirmed)))
        await store.receive(.blockConfirmed)

        #expect(store.state.alert != nil)
    }

    @MainActor @Test func copyWritesTheFullKeyNotTheAbbreviatedOne() async {
        let copied = LockIsolated<String?>(nil)
        let clock = DispatchQueue.test
        let store = editStore(ChatContact(publicKey: peerKey, name: "Ada")) {
            $0.pasteboard.setString = { copied.setValue($0.data) }
            $0.mainQueue = clock.eraseToAnyScheduler()
        }

        await store.send(.copyTapped(.publicKey)) {
            $0.copiedField = .publicKey
        }
        #expect(copied.value == peerKey)

        await clock.advance(by: .seconds(2))
        await store.receive(.copyIndicatorExpired) {
            $0.copiedField = nil
        }
    }
}
