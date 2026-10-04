//
//  GroupInfoSheetTests.swift
//  zodlTests
//
//  Group info as Android's `GroupInfoSheet`: presented over the room from its title, owner-only
//  controls, and leaving closes the room as well.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal
import ZappMessaging

@Suite(.serialized) struct GroupInfoSheetTests {
    private static let peerKey = String(repeating: "b", count: PublicKeyRules.hexLength)

    private static func group(name: String = "Team", isOwner: Bool? = true) -> ZMConversation {
        ZMConversation(
            id: "group",
            type: .group,
            participantIds: [peerKey],
            displayName: name,
            // Pinned: the default is `Date()`, which would make two copies unequal.
            createdAt: Date(timeIntervalSince1970: 0),
            isOwner: isOwner
        )
    }

    @MainActor @Test func aGroupTitleOpensGroupInfoOverTheRoom() async {
        let store = TestStore(
            initialState: ChatRoom.State(conversationId: "group", conversation: Self.group())
        ) {
            ChatRoom()
        }
        // `GroupInfo.State` mints a fresh cancel id per instance, so it is compared by field.
        store.exhaustivity = .off

        await store.send(.titleTapped)

        #expect(store.state.groupInfo?.conversation == Self.group())
        #expect(store.state.contactForm == nil)
    }

    @MainActor @Test func aDirectTitleDoesNotOpenGroupInfo() async {
        let direct = ZMConversation(id: "dm", type: .direct, participantIds: [Self.peerKey], displayName: "Alice")
        let store = TestStore(initialState: ChatRoom.State(conversationId: "dm", conversation: direct)) {
            ChatRoom()
        }
        store.exhaustivity = .off

        await store.send(.titleTapped)

        #expect(store.state.groupInfo == nil)
        #expect(store.state.contactForm != nil)
    }

    /// A rename seen by the sheet carries into the room header, so the title is current
    /// once the sheet closes.
    @MainActor @Test func aRenameInTheSheetUpdatesTheRoomTitle() async {
        var state = ChatRoom.State(conversationId: "group", conversation: Self.group())
        state.groupInfo = GroupInfo.State(conversation: Self.group())
        let store = TestStore(initialState: state) {
            ChatRoom()
        }

        await store.send(.groupInfo(.presented(.conversationsChanged([Self.group(name: "Renamed")])))) {
            $0.groupInfo?.conversation = Self.group(name: "Renamed")
            $0.conversation = Self.group(name: "Renamed")
        }

        #expect(store.state.title == "Renamed")
    }

    @MainActor @Test func leavingClosesTheSheet() async {
        var state = ChatRoom.State(conversationId: "group", conversation: Self.group())
        state.groupInfo = GroupInfo.State(conversation: Self.group())
        let store = TestStore(initialState: state) {
            ChatRoom()
        }

        await store.send(.groupInfo(.presented(.didLeave))) {
            $0.groupInfo = nil
        }
    }

    /// Android offers Add member to the owner only; iOS keeps rename owner-only too.
    @MainActor @Test func onlyTheOwnerIsOfferedRenameAndAddMember() async {
        let store = TestStore(initialState: GroupInfo.State(conversation: Self.group(isOwner: false))) {
            GroupInfo()
        }

        #expect(!store.state.canAddMember)
        #expect(!store.state.canRename)

        await store.send(.addMemberTapped)
        await store.send(.renameTapped)

        #expect(GroupInfo.State(conversation: Self.group(isOwner: true)).canAddMember)
    }
}
