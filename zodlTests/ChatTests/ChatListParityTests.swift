//
//  ChatListParityTests.swift
//  zodlTests
//
//  Phase 4 of the Android parity work: swipe-to-leave confirmation, the messaging-terms gate,
//  and the last-message preview mapping (Features/Chats/ChatsListStore.swift,
//  Features/Chats/ChatConversationRow.swift).
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

// Touches `@Shared(.appStorage(.chatTermsAccepted))`, which is process-global.
@Suite(.serialized) struct ChatListParityTests {
    private func conversation(id: String = "conversation", isGroup: Bool = false) -> ZMConversation {
        ZMConversation(
            id: id,
            type: isGroup ? .group : .direct,
            participantIds: [id],
            displayName: "chinmay"
        )
    }

    // MARK: - Swipe / context-menu leave

    @MainActor @Test func leavingAConversationConfirmsBeforeRemovingIt() async {
        let direct = conversation()
        var state = ChatsList.State()
        state.conversations = [direct]

        let removed = LockIsolated<[String]>([])

        let store = TestStore(initialState: state) {
            ChatsList()
        } withDependencies: {
            $0.zappMessaging.removeConversation = { id in removed.withValue { $0.append(id) } }
        }

        await store.send(.leaveConversationRequested(direct.id)) {
            $0.alert = AlertState.leaveConversation(id: direct.id, name: "chinmay")
        }

        #expect(removed.value.isEmpty)

        await store.send(.alert(.presented(.leaveConfirmed(direct.id)))) {
            $0.alert = nil
        }
        await store.receive(\.removeConversationTapped)

        #expect(removed.value == [direct.id])
    }

    @MainActor @Test func groupConversationsLeaveThroughTheSameConfirmedPath() async {
        let group = conversation(id: "group", isGroup: true)
        var state = ChatsList.State()
        state.conversations = [group]

        let store = TestStore(initialState: state) { ChatsList() }

        await store.send(.leaveConversationRequested(group.id)) {
            $0.alert = AlertState.leaveConversation(id: group.id, name: "chinmay")
        }
    }

    @MainActor @Test func dismissingTheLeaveAlertKeepsTheConversation() async {
        let direct = conversation()
        var state = ChatsList.State()
        state.conversations = [direct]

        let removed = LockIsolated(false)

        let store = TestStore(initialState: state) {
            ChatsList()
        } withDependencies: {
            $0.zappMessaging.removeConversation = { _ in removed.setValue(true) }
        }

        await store.send(.leaveConversationRequested(direct.id)) {
            $0.alert = AlertState.leaveConversation(id: direct.id, name: "chinmay")
        }

        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }

        #expect(!removed.value)
    }

    @MainActor @Test func leaveRequestForAnUnknownConversationIsIgnored() async {
        let store = TestStore(initialState: ChatsList.State()) { ChatsList() }

        await store.send(.leaveConversationRequested("missing"))

        #expect(store.state.alert == nil)
    }

    // MARK: - Messaging terms gate

    @MainActor @Test func termsGateOpensOnFirstEntryAndPersistsAcceptance() async {
        let store = TestStore(initialState: ChatsList.State()) {
            ChatsList()
        } withDependencies: {
            $0.mainQueue = .immediate
        }
        store.exhaustivity = .off

        store.state.$chatTermsAccepted.withLock { $0 = false }

        await store.send(.onAppear)
        #expect(store.state.showsTermsDialog)

        await store.send(.termsAccepted)
        #expect(!store.state.showsTermsDialog)
        #expect(store.state.chatTermsAccepted)

        await store.send(.onDisappear)
        await store.send(.onAppear)
        #expect(!store.state.showsTermsDialog)

        await store.send(.onDisappear)
    }

    @MainActor @Test func decliningTheTermsClosesTheGateWithoutAcceptingIt() async {
        let store = TestStore(initialState: ChatsList.State()) {
            ChatsList()
        } withDependencies: {
            $0.mainQueue = .immediate
        }
        store.exhaustivity = .off

        store.state.$chatTermsAccepted.withLock { $0 = false }

        await store.send(.onAppear)
        #expect(store.state.showsTermsDialog)

        await store.send(.termsDeclined)
        #expect(!store.state.showsTermsDialog)
        #expect(!store.state.chatTermsAccepted)

        // The gate is re-presented on the next entry to the tab, as on Android.
        await store.send(.onDisappear)
        await store.send(.onAppear)
        #expect(store.state.showsTermsDialog)

        await store.send(.onDisappear)
    }

    @MainActor @Test func decliningTheTermsReturnsToThePreviouslySelectedTab() async {
        var state = ZappTabs.State()
        state.selectedTab = .pay

        let store = TestStore(initialState: state) { ZappTabs() }

        await store.send(.tabSelected(.chats)) {
            $0.previousTab = .pay
            $0.selectedTab = .chats
        }

        // Re-tapping the live tab must not overwrite where a decline returns to.
        await store.send(.tabSelected(.chats))

        #expect(store.state.previousTab == .pay)
    }

    // MARK: - Row preview parity

    @Test func everyStructuredSentinelGetsItsOwnPreviewLabel() {
        let labels = [
            "[Media]", "[Photo]", "[GIF]", "[Video]", "[File]",
            "[Location]", "[Payment]", "[PaymentRequest]"
        ].map { ChatPreviewSentinel.label(for: $0) }

        #expect(labels.allSatisfy { $0 != nil })
        // Android maps each sentinel to a distinct string; iOS used to collapse them all.
        #expect(Set(labels.compactMap { $0 }).count == labels.count)
        #expect(ChatPreviewSentinel.label(for: "See you at 8") == nil)
    }

    @Test func coldLoadedJsonIsLabelledAndNeverShownRaw() {
        let request = "{\"id\":\"abc\",\"amount\":1}"
        let requestByMarker = "{\"foo\":1,\"requesterAddress\":\"u1abc\"}"
        let transaction = "{\"txId\":\"abc\"}"

        #expect(ChatPreviewSentinel.jsonLabel(for: request) == String(localizable: .chatListPaymentRequestPlaceholder))
        #expect(
            ChatPreviewSentinel.jsonLabel(for: requestByMarker)
                == String(localizable: .chatListPaymentRequestPlaceholder)
        )
        #expect(ChatPreviewSentinel.jsonLabel(for: transaction) == String(localizable: .chatListPaymentPlaceholder))
        #expect(ChatPreviewSentinel.jsonLabel(for: "plain text") == nil)
    }

    // MARK: - Sorting

    @Test func blockedDirectConversationsStayHiddenWhileGroupsDoNot() {
        let blockedKey = String(repeating: "b", count: PublicKeyRules.hexLength)

        var state = ChatsList.State()
        defer { state.$chatContacts.withLock { $0 = .empty } }

        state.$chatContacts.withLock {
            $0 = ChatContacts(
                lastUpdated: .distantPast,
                version: ChatContacts.Constants.version,
                contacts: [ChatContact(publicKey: blockedKey, name: "blocked", isBlocked: true, isSaved: false)]
            )
        }
        state.conversations = [
            ZMConversation(id: "blocked", type: .direct, participantIds: [blockedKey], displayName: "blocked"),
            ZMConversation(id: "group", type: .group, participantIds: [blockedKey], displayName: "group")
        ]

        #expect(state.sortedConversations.map(\.id) == ["group"])
    }
}
