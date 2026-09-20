//
//  GroupInviteStoreTests.swift
//  zodlTests
//

import Combine
import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

/// The joiner's screen, from reading a link to the answer. Every transition matches Android's
/// `GroupInviteMachine`, because the same tapped link has to say the same thing on either phone.
@Suite(.serialized) struct GroupInviteStoreTests {
    private static let link = "https://join.justzappit.xyz/g/v1#AQGLmx_sGDZTw7Gb8xx8Wp7a36GI8igPwlPzx"
    private static let linkId = "c0ffee"

    @MainActor private func makeStore(
        pending: PendingGroupInviteStore,
        token: String?,
        comingSoon: Bool = false,
        inspection: ZMGroupLinkInspection = ZMGroupLinkInspection(
            status: .ok,
            nameHint: "Hiking Crew",
            linkId: GroupInviteStoreTests.linkId
        ),
        joinResult: ZMGroupJoinResult = ZMGroupJoinResult(status: .requested, linkId: GroupInviteStoreTests.linkId),
        joinThrows: Bool = false,
        updates: PassthroughSubject<ZMGroupJoinUpdate, Never> = .init(),
        joins: LockIsolated<Int> = LockIsolated(0),
        cancelled: LockIsolated<[String]> = LockIsolated([])
    ) -> TestStoreOf<GroupInvite> {
        TestStore(initialState: GroupInvite.State(token: token, comingSoon: comingSoon)) {
            GroupInvite()
        } withDependencies: {
            $0.pendingGroupInvites = pending
            $0.zappMessaging.inspectGroupLink = { _ in inspection }
            $0.zappMessaging.joinGroupViaLink = { _ in
                joins.withValue { $0 += 1 }
                if joinThrows { throw ZMError.notInitialized }
                return joinResult
            }
            $0.zappMessaging.groupJoinStatus = { [] }
            $0.zappMessaging.cancelGroupJoin = { linkId in
                cancelled.withValue { $0.append(linkId) }
                return true
            }
            $0.zappMessaging.groupJoinUpdatesStream = { updates.eraseToAnyPublisher() }
        }
    }

    private func held() -> (PendingGroupInviteStore, String) {
        let store = PendingGroupInviteStore(persistence: .inMemory())
        guard case .accepted(let token) = store.put(Self.link) else {
            fatalError("the test link is a group link")
        }
        return (store, token)
    }

    @MainActor @Test func readingALinkContactsNobodyAndKeepsIt() async {
        let (pending, token) = held()
        let store = makeStore(pending: pending, token: token)
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected) {
            $0.stage = .preview(nameHint: "Hiking Crew")
            $0.linkId = Self.linkId
        }

        #expect(pending.link(for: token) == Self.link, "the link is kept until the person answers")
        await store.send(.teardown)
    }

    @MainActor @Test func joiningWaitsAndTheSecretIsDeletedOnceTheSDKHoldsTheRequest() async {
        let (pending, token) = held()
        let joins = LockIsolated(0)
        let store = makeStore(pending: pending, token: token, joins: joins)
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected)
        await store.send(.joinTapped)
        await store.receive(\.joinAnswered) {
            $0.stage = .waiting(linkId: Self.linkId, withOwner: false)
            $0.token = nil
        }

        #expect(joins.value == 1)
        #expect(pending.link(for: token) == nil, "the SDK holds the request now")
        await store.send(.teardown)
    }

    @MainActor @Test func aRequestThatNeverLeftTheDeviceKeepsTheLinkAndSaysSo() async {
        let (pending, token) = held()
        let store = makeStore(pending: pending, token: token, joinThrows: true)
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected)
        await store.send(.joinTapped)
        await store.receive(\.joinFailed) {
            $0.sendFailed = true
            $0.stage = .preview(nameHint: "Hiking Crew")
        }

        #expect(pending.link(for: token) == Self.link, "nothing left the device, so the link stays")
        await store.send(.teardown)
    }

    @MainActor @Test func theOwnersAnswerArrivesLaterOnTheStream() async {
        let (pending, token) = held()
        let updates = PassthroughSubject<ZMGroupJoinUpdate, Never>()
        let store = makeStore(pending: pending, token: token, updates: updates)
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected)
        await store.send(.joinTapped)
        await store.receive(\.joinAnswered)

        updates.send(ZMGroupJoinUpdate(linkId: Self.linkId, status: .pendingApproval))
        await store.receive(\.updated) {
            $0.stage = .waiting(linkId: Self.linkId, withOwner: true)
        }

        updates.send(ZMGroupJoinUpdate(linkId: Self.linkId, status: .declined))
        await store.receive(\.updated) {
            $0.stage = .failed(.declined)
        }

        await store.send(.teardown)
    }

    @MainActor @Test func joiningAGroupAlreadyJoinedOffersItRatherThanAskingAgain() async {
        let (pending, token) = held()
        let store = makeStore(
            pending: pending,
            token: token,
            joinResult: ZMGroupJoinResult(status: .alreadyMember, linkId: Self.linkId, conversationId: "g1")
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected)
        await store.send(.joinTapped)
        await store.receive(\.joinAnswered) {
            $0.stage = .joined(conversationId: "g1", nameHint: "Hiking Crew", alreadyMember: true)
            $0.token = nil
        }

        await store.send(.openGroupTapped("g1"))
        await store.receive(\.delegate)
        await store.send(.teardown)
    }

    @MainActor @Test func anExpiredLinkFailsBeforeAnyRequestAndIsDeleted() async {
        let (pending, token) = held()
        let joins = LockIsolated(0)
        let store = makeStore(
            pending: pending,
            token: token,
            inspection: ZMGroupLinkInspection(status: .expired, linkId: Self.linkId),
            joins: joins
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected) {
            $0.stage = .failed(.expired)
            $0.linkId = Self.linkId
            $0.token = nil
        }

        #expect(joins.value == 0, "a link that cannot work is never sent anywhere")
        #expect(pending.link(for: token) == nil)
        await store.send(.teardown)
    }

    @MainActor @Test func aLinkFromANewerFormatAsksForAnUpdate() async {
        let (pending, token) = held()
        let store = makeStore(
            pending: pending,
            token: token,
            inspection: ZMGroupLinkInspection(status: .newerFormat, linkId: Self.linkId)
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected) {
            $0.stage = .failed(.needsUpdate)
            $0.linkId = Self.linkId
            $0.token = nil
        }

        await store.send(.teardown)
    }

    @MainActor @Test func aRefusedLinkAndTheFlagOffEachLandSomewhere() async {
        let refused = makeStore(pending: PendingGroupInviteStore(persistence: .inMemory()), token: nil)
        refused.exhaustivity = .off
        await refused.send(.onAppear) {
            $0.stage = .failed(.unreadable)
        }

        let comingSoon = makeStore(
            pending: PendingGroupInviteStore(persistence: .inMemory()),
            token: nil,
            comingSoon: true
        )
        comingSoon.exhaustivity = .off
        await comingSoon.send(.onAppear) {
            $0.stage = .comingSoon
        }
    }

    @MainActor @Test func cancellingTakesTheRequestBack() async {
        let (pending, token) = held()
        let cancelled = LockIsolated<[String]>([])
        let store = makeStore(pending: pending, token: token, cancelled: cancelled)
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.inspected)
        await store.send(.joinTapped)
        await store.receive(\.joinAnswered)

        await store.send(.cancelTapped)
        await store.receive(\.delegate)

        #expect(cancelled.value == [Self.linkId])
        await store.send(.teardown)
    }
}
