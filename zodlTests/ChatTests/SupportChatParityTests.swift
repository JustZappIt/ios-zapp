//
//  SupportChatParityTests.swift
//  zodlTests
//
//  Phase 7 of the Android parity work: the Zapp Support subsystem
//  (Features/Chats/SupportChatConstants.swift, SupportChatStore.swift,
//  SupportTicketListStore.swift, and the pinned row in ChatsListStore.swift).
//
//  The load-bearing rule here is that a support ticket is an ORDINARY conversation with a known
//  peer — no new wire format — so these tests pin the client-side conventions that make it read
//  as support on both platforms: the side-asymmetric classification, the `[Zapp]:` prefix, and
//  the `[Category: …]` marker.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

/// Shared across the suites below; file-scope so the `@MainActor` suites' dependency closures can
/// read them without crossing an actor boundary.
private let supportAgentKey = SupportChatConstants.supportPublicKey
private let supportTestUserKey = String(repeating: "a", count: 64)

@Suite struct SupportChatConstantsTests {
    // MARK: - Side-asymmetric classification

    /// The user's device must see the agent's key among the participants. A `Support: …` display
    /// name is attacker-controlled, so it alone must NOT promote a stranger to the support row.
    @Test func theUserSideRequiresTheSupportKeyAndIgnoresTheDisplayName() {
        #expect(
            SupportChatConstants.isSupportConversation(
                displayName: "Support: Problem",
                participantIds: [supportAgentKey],
                localPublicKey: supportTestUserKey
            )
        )

        #expect(
            !SupportChatConstants.isSupportConversation(
                displayName: "Support: Problem",
                participantIds: [String(repeating: "b", count: 64)],
                localPublicKey: supportTestUserKey
            )
        )

        // No display-name prefix at all is still a ticket for the user: the key is what counts.
        #expect(
            SupportChatConstants.isSupportConversation(
                displayName: "anything",
                participantIds: [supportAgentKey],
                localPublicKey: supportTestUserKey
            )
        )
    }

    /// The agent's device cannot use that test: the SDK omits the LOCAL user's own key from
    /// `participantIds`, so the agent never sees itself listed. It falls back to the prefix.
    @Test func theSupportAgentSideFallsBackToTheDisplayNamePrefix() {
        #expect(
            SupportChatConstants.isSupportConversation(
                displayName: "Support: Feedback",
                participantIds: [supportTestUserKey],
                localPublicKey: supportAgentKey
            )
        )

        #expect(
            !SupportChatConstants.isSupportConversation(
                displayName: "chinmay",
                participantIds: [supportTestUserKey],
                localPublicKey: supportAgentKey
            )
        )

        // The exact inversion of the user-side rule: on the agent's device the participant list
        // decides nothing.
        #expect(
            !SupportChatConstants.isSupportConversation(
                displayName: "chinmay",
                participantIds: [supportAgentKey],
                localPublicKey: supportAgentKey
            )
        )
    }

    /// Before the identity lands there is no local key, and the safe branch is the user's.
    @Test func anUnknownLocalIdentityTakesTheUserBranch() {
        #expect(
            SupportChatConstants.isSupportConversation(
                displayName: "Support: Other",
                participantIds: [supportAgentKey],
                localPublicKey: nil
            )
        )

        #expect(
            !SupportChatConstants.isSupportConversation(
                displayName: "Support: Other",
                participantIds: [supportTestUserKey],
                localPublicKey: nil
            )
        )
    }

    // MARK: - Wire conventions

    @Test func theCategoryMarkerRoundTripsThroughItsProtocolKey() {
        for category in SupportCategory.allCases {
            let marker = SupportChatConstants.categoryMarker(for: category)

            #expect(marker == "[Category: \(category.protocolKey)]")
            #expect(SupportChatConstants.parseCategoryMarker(marker) == category)
        }

        #expect(SupportChatConstants.parseCategoryMarker("[Category: Nonsense]") == nil)
        #expect(SupportChatConstants.parseCategoryMarker("Please describe the issue") == nil)
    }

    /// The protocol keys travel on the wire and must never be localized.
    @Test func theProtocolKeysMatchAndroidVerbatim() {
        #expect(SupportCategory.allCases.map(\.protocolKey) == ["Problem", "Feedback", "Other"])
        #expect(SupportChatConstants.displayNamePrefix == "Support: ")
        #expect(SupportChatConstants.botPrefix == "[Zapp]: ")
        #expect(
            SupportChatConstants.conversationDisplayName(for: .problem) == "Support: Problem"
        )
    }

    @Test func strippingTheBotPrefixLeavesEverythingElseAlone() {
        #expect(SupportChatConstants.stripBotPrefix("[Zapp]: How can we help?") == "How can we help?")
        #expect(SupportChatConstants.stripBotPrefix("How can we help?") == "How can we help?")
    }

    // MARK: - Message mapping

    private func message(id: String, content: String, isFromMe: Bool) -> ZMMessage {
        ZMMessage(
            id: id,
            conversationId: "ticket",
            senderId: isFromMe ? supportTestUserKey : supportAgentKey,
            content: content,
            timestamp: Date(timeIntervalSince1970: 1),
            isFromMe: isFromMe
        )
    }

    /// The greeting and the leave notice are posted BY the user's own device, so `isFromMe` would
    /// put them on the wrong side. The prefix — not ownership — decides.
    @Test func botPrefixedMessagesRenderAsSystemMessagesWhoeverSentThem() {
        let ownGreeting = SupportMessage.from(
            message(id: "1", content: "[Zapp]: How can we help?", isFromMe: true)
        )

        #expect(ownGreeting?.origin == .bot)
        #expect(ownGreeting?.isFromLocalUser == false)
        #expect(ownGreeting?.content == "How can we help?")

        let agentAnnouncement = SupportMessage.from(
            message(id: "2", content: "[Zapp]: User has left the chat.", isFromMe: false)
        )

        #expect(agentAnnouncement?.origin == .bot)
    }

    @Test func ordinaryMessagesKeepTheirOwnership() {
        #expect(SupportMessage.from(message(id: "1", content: "hi", isFromMe: true))?.origin == .user)
        #expect(SupportMessage.from(message(id: "2", content: "hi", isFromMe: false))?.origin == .agent)
    }

    /// The marker is protocol traffic; rendering it would show the user `[Category: Problem]`.
    @Test func theCategoryMarkerIsNeverRendered() {
        #expect(SupportMessage.from(message(id: "1", content: "[Category: Problem]", isFromMe: true)) == nil)
    }
}

// MARK: - Chat list pinning

@Suite struct SupportChatListRowTests {
    private func ticket(
        id: String,
        lastMessage: String? = nil,
        secondsAgo: TimeInterval = 0
    ) -> ZMConversation {
        ZMConversation(
            id: id,
            type: .group,
            participantIds: [supportAgentKey],
            displayName: "Support: Problem",
            lastMessage: lastMessage,
            lastMessageTimestamp: Date(timeIntervalSince1970: 1_000 - secondsAgo)
        )
    }

    private func listState(_ conversations: [ZMConversation]) -> ChatsList.State {
        var state = ChatsList.State()
        state.conversations = conversations
        state.messagingState.identity = ZMIdentity(publicKey: supportTestUserKey, displayName: "me")
        return state
    }

    @Test func supportConversationsAreSplitOutOfTheOrdinaryList() {
        let ordinary = ZMConversation(
            id: "chat",
            type: .direct,
            participantIds: [String(repeating: "c", count: 64)],
            displayName: "chinmay"
        )
        let state = listState([ticket(id: "ticket"), ordinary])

        #expect(state.sortedConversations.map(\.id) == ["chat"])
        #expect(state.supportConversations.map(\.id) == ["ticket"])
    }

    @Test func theSubtitleIsTheLatestSupportMessageWithoutItsBotPrefix() {
        let state = listState([
            ticket(id: "old", lastMessage: "older", secondsAgo: 500),
            ticket(id: "new", lastMessage: "[Zapp]: How can we help?")
        ])

        #expect(state.supportRowSubtitle == "How can we help?")
    }

    /// Android reads the NEWEST ticket's last message — not the newest message across tickets —
    /// so a brand-new empty ticket falls through to the count rather than quoting an older one.
    @Test func aNewestTicketWithNoMessagesFallsBackToTheOpenTicketCount() {
        let state = listState([
            ticket(id: "old", lastMessage: "older", secondsAgo: 500),
            ticket(id: "new", lastMessage: nil)
        ])

        #expect(state.supportRowSubtitle == String(localizable: .chatListSupportTickets("2")))
    }

    @Test func withNoTicketsTheRowShowsItsDefaultInvitation() {
        let state = listState([])

        #expect(state.supportRowSubtitle == String(localizable: .chatListSupportSubtitleDefault))
        #expect(state.supportUnreadCount == 0)
    }

    /// The preview guarantee from Phase 4 still holds inside support: a media sentinel or a JSON
    /// body must never reach the row verbatim.
    @Test func structuredSupportMessagesAreLabelledRatherThanShownRaw() {
        #expect(SupportPreview.subtitle(for: "[Zapp]: [Photo]") == String(localizable: .chatListPhotoPlaceholder))
        #expect(
            SupportPreview.subtitle(for: "{\"txId\":\"abc\"}") == String(localizable: .chatListPaymentPlaceholder)
        )
    }

    @Test func unreadCountsAggregateAcrossEveryOpenTicket() {
        var state = listState([ticket(id: "one"), ticket(id: "two")])
        state.messagingState.unreadCounts = ["one": 2, "two": 3, "elsewhere": 7]

        #expect(state.supportUnreadCount == 5)
    }
}

// MARK: - Ticket list

@Suite @MainActor struct SupportTicketListTests {
    private func state(_ conversations: [ZMConversation]) -> SupportTicketList.State {
        var state = SupportTicketList.State()
        state.conversations = conversations
        state.isLoaded = true
        state.messagingState.identity = ZMIdentity(publicKey: supportTestUserKey, displayName: "me")
        return state
    }

    private func ticketConversation(id: String) -> ZMConversation {
        ZMConversation(
            id: id,
            type: .group,
            participantIds: [supportAgentKey],
            displayName: "Support: Feedback",
            lastMessage: "[Zapp]: We’d love to hear your thoughts.",
            lastMessageTimestamp: Date(timeIntervalSince1970: 1_000)
        )
    }

    /// One conversation per ticket: the topic picker creates a new group every time, so the list
    /// is an inbox of conversations rather than threads inside one.
    @Test func eachSupportConversationBecomesOneTicketRow() {
        let ordinary = ZMConversation(
            id: "chat",
            type: .direct,
            participantIds: [String(repeating: "c", count: 64)],
            displayName: "chinmay"
        )
        let listState = state([ticketConversation(id: "one"), ordinary])

        #expect(listState.tickets.map(\.conversationId) == ["one"])
        #expect(listState.tickets.first?.lastMessage == "We’d love to hear your thoughts.")
        #expect(listState.tickets.first?.categoryLabel == String(localizable: .supportTicketDefaultLabel))
    }

    @Test func theTopicIsRecoveredFromTheTicketsCategoryMarker() async {
        let store = TestStore(initialState: SupportTicketList.State()) {
            SupportTicketList()
        } withDependencies: {
            $0.zappMessaging.messages = { conversationId, _ in
                [
                    ZMMessage(
                        id: "marker",
                        conversationId: conversationId,
                        senderId: supportTestUserKey,
                        content: "[Category: Feedback]",
                        timestamp: Date(timeIntervalSince1970: 1),
                        isFromMe: true
                    )
                ]
            }
        }
        store.exhaustivity = .off

        await store.send(.messagingStateChanged(makeState()))
        await store.send(.conversationsUpdated([ticketConversation(id: "one")]))
        await store.receive(\.categoriesLoaded)

        #expect(store.state.categories["one"] == .feedback)
        #expect(store.state.tickets.first?.categoryLabel == SupportCategory.feedback.displayName)

        // A resolved id is never looked up twice.
        await store.send(.conversationsUpdated([ticketConversation(id: "one")]))
        #expect(store.state.resolvedCategoryIds == ["one"])
    }

    @Test func closingATicketConfirmsThenPostsTheLeaveNoticeBeforeRemovingIt() async {
        let sent = LockIsolated<[String]>([])
        let removed = LockIsolated<[String]>([])

        let store = TestStore(initialState: state([ticketConversation(id: "one")])) {
            SupportTicketList()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { _, content, _ in
                sent.withValue { $0.append(content) }
                return ZMMessage(
                    id: "notice",
                    conversationId: "one",
                    senderId: supportTestUserKey,
                    content: content,
                    timestamp: Date(timeIntervalSince1970: 2),
                    isFromMe: true
                )
            }
            $0.zappMessaging.removeConversation = { id in removed.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.closeTicketRequested("one"))
        #expect(store.state.alert != nil)
        #expect(removed.value.isEmpty)

        await store.send(.alert(.presented(.closeConfirmed("one"))))
        await store.finish()

        #expect(sent.value == ["\(SupportChatConstants.botPrefix)\(String(localizable: .supportChatLeaveNotice))"])
        #expect(removed.value == ["one"])
    }

    private func makeState() -> ZappMessagingState {
        var messagingState = ZappMessagingState()
        messagingState.identity = ZMIdentity(publicKey: supportTestUserKey, displayName: "me")
        return messagingState
    }
}

// MARK: - Support chat

@Suite @MainActor struct SupportChatTicketCreationTests {
    /// The whole topic picker, on the wire: one group whose only remote member is the support
    /// agent, then the category marker, then the bot-prefixed greeting. Nothing else.
    @Test func pickingATopicCreatesTheTicketAndSeedsItLikeAndroid() async {
        let createdGroups = LockIsolated<[(String, [String])]>([])
        let sent = LockIsolated<[String]>([])

        let store = TestStore(initialState: SupportChat.State()) {
            SupportChat()
        } withDependencies: {
            $0.zappMessaging.createGroup = { name, participants in
                createdGroups.withValue { $0.append((name, participants)) }
                return ZMConversation(
                    id: "ticket",
                    type: .group,
                    participantIds: participants,
                    displayName: name
                )
            }
            $0.zappMessaging.sendMessage = { conversationId, content, _ in
                sent.withValue { $0.append(content) }
                return ZMMessage(
                    id: "msg-\(sent.value.count)",
                    conversationId: conversationId,
                    senderId: supportTestUserKey,
                    content: content,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(sent.value.count)),
                    isFromMe: true
                )
            }
            $0.zappMessaging.setActiveConversation = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        #expect(store.state.mode == .selectCategory(isSubmitting: false))

        await store.send(.categorySelected(.problem))
        await store.receive(\.ticketCreated)
        await store.receive(\.messageReceived)
        await store.finish()

        #expect(createdGroups.value.map(\.0) == ["Support: Problem"])
        #expect(createdGroups.value.map(\.1) == [[SupportChatConstants.supportPublicKey]])
        #expect(
            sent.value == [
                "[Category: Problem]",
                "\(SupportChatConstants.botPrefix)\(SupportCategory.problem.greeting)"
            ]
        )

        #expect(store.state.conversationId == "ticket")
        #expect(store.state.mode == .chat)
        // The marker never becomes a bubble; the greeting does, on the bot's side.
        #expect(store.state.messages.map(\.origin) == [.bot])
        #expect(store.state.messages.first?.content == SupportCategory.problem.greeting)
    }

    @Test func aNewTicketOpensOnTheTopicPickerAndAnExistingOneOnTheChat() async {
        let picker = TestStore(initialState: SupportChat.State()) {
            SupportChat()
        } withDependencies: {
            $0.zappMessaging.setActiveConversation = { _ in }
        }
        picker.exhaustivity = .off

        await picker.send(.onAppear)
        #expect(picker.state.mode == .selectCategory(isSubmitting: false))
        await picker.send(.onDisappear)

        let existing = TestStore(initialState: SupportChat.State(conversationId: "ticket")) {
            SupportChat()
        } withDependencies: {
            $0.zappMessaging.markRead = { _ in }
            $0.zappMessaging.messages = { _, _ in [] }
            $0.zappMessaging.setActiveConversation = { _ in }
        }
        existing.exhaustivity = .off

        await existing.send(.onAppear)
        await existing.receive(\.messagesLoaded)
        #expect(existing.state.mode == .chat)
        await existing.send(.onDisappear)
    }

    /// A user message is plain text: only automated messages carry the prefix.
    @Test func sendingAMessageNeverAddsTheBotPrefix() async {
        let sent = LockIsolated<[String]>([])

        let store = TestStore(initialState: SupportChat.State(conversationId: "ticket")) {
            SupportChat()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { conversationId, content, _ in
                sent.withValue { $0.append(content) }
                return ZMMessage(
                    id: "sent",
                    conversationId: conversationId,
                    senderId: supportTestUserKey,
                    content: content,
                    timestamp: Date(timeIntervalSince1970: 5),
                    isFromMe: true
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.draftChanged("  my app crashed  "))
        await store.send(.sendTapped)
        await store.receive(\.sendSucceeded)
        await store.finish()

        #expect(sent.value == ["my app crashed"])
        #expect(store.state.draft.isEmpty)
        #expect(store.state.messages.map(\.origin) == [.user])
    }

    /// A failed send hands the text back rather than losing it.
    @Test func aFailedSendRestoresTheDraft() async {
        let store = TestStore(initialState: SupportChat.State(conversationId: "ticket")) {
            SupportChat()
        } withDependencies: {
            $0.zappMessaging.sendMessage = { _, _, _ in throw ZMError.notInitialized }
        }
        store.exhaustivity = .off

        await store.send(.draftChanged("hello"))
        await store.send(.sendTapped)
        await store.receive(\.sendFailed)
        await store.finish()

        #expect(store.state.draft == "hello")
        #expect(store.state.sendDidFail)
    }
}

// MARK: - Routing

// Serialized: drives a Root store sharing process-global `@Shared` state.
@Suite(.serialized) @MainActor struct SupportChatRoutingTests {
    private func rootStore() -> StoreOf<Root> {
        Store(initialState: .initial) {
            Root()
        } withDependencies: {
            $0.mainQueue = .immediate
            $0.sdkSynchronizer = .noOp
            $0.walletStorage = .noOp
        }
    }

    /// The pinned row opens the TICKET LIST, not a chat room — the row aggregates every ticket.
    @Test func theSupportRowOpensTheTicketList() {
        let store = rootStore()

        store.send(.chatsList(.supportRowTapped))

        #expect(store.path == .supportTicketList)
    }

    @Test func aTicketOpensTheSupportChatAndBackReturnsToTheList() {
        let store = rootStore()

        store.send(.chatsList(.supportRowTapped))
        store.send(.supportTicketList(.ticketTapped("ticket")))

        #expect(store.path == .supportChat)
        #expect(store.supportChatState.conversationId == "ticket")

        store.send(.supportChat(.backTapped))
        #expect(store.path == .supportTicketList)
    }

    @Test func newTicketOpensTheSupportChatWithoutAConversation() {
        let store = rootStore()

        store.send(.supportTicketList(.newTicketTapped))

        #expect(store.path == .supportChat)
        #expect(store.supportChatState.conversationId == nil)
    }

    /// Closing the ticket from inside the chat unwinds to the list, never to a dead screen.
    @Test func closingATicketUnwindsToTheTicketList() {
        let store = rootStore()

        store.send(.supportTicketList(.ticketTapped("ticket")))
        store.send(.supportChat(.leaveFinished))

        #expect(store.path == .supportTicketList)
    }
}
