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
        let left = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.leaveConversation = { id in left.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.groupInfo(.presented(.leaveConfirmed)))
        await store.receive(\.leftGroup) {
            $0.groupInfo = nil
        }
        #expect(left.value == ["group"])
    }

    /// The room runs the leave, so swiping the sheet away mid-call doesn't cancel it: the room
    /// still hears it finished and Root closes the room.
    @MainActor @Test func dismissingTheSheetMidLeaveStillLeaves() async {
        var state = ChatRoom.State(conversationId: "group", conversation: Self.group())
        state.groupInfo = GroupInfo.State(conversation: Self.group())
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.leaveConversation = { _ in
                for await _ in gate.stream { break }
            }
        }
        store.exhaustivity = .off

        await store.send(.groupInfo(.presented(.leaveConfirmed)))
        await store.send(.groupInfo(.dismiss))
        #expect(store.state.groupInfo == nil)

        gate.continuation.yield()
        await store.receive(\.leftGroup)
    }

    /// Android counts every participant, us included; the roster leaves us out.
    @Test func theMemberCountIncludesUs() {
        let ownKey = String(repeating: "a", count: PublicKeyRules.hexLength)
        let otherKey = String(repeating: "c", count: PublicKeyRules.hexLength)
        func group(_ keys: [String]) -> GroupInfo.State {
            var state = GroupInfo.State(conversation: ZMConversation(
                id: "group",
                type: .group,
                participantIds: keys,
                displayName: "Team",
                createdAt: Date(timeIntervalSince1970: 0),
                isOwner: true
            ))
            state.localPublicKey = ownKey
            return state
        }

        let withoutUs = group([Self.peerKey, otherKey])
        #expect(withoutUs.members.count == 2)
        #expect(withoutUs.memberCount == 3)

        // Our key listed among the participants is not counted twice.
        #expect(group([Self.peerKey, otherKey, ownKey]).memberCount == 3)
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
