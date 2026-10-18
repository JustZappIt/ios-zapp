import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(1)))
struct GroupInviteRegressionTests {
    private static let link = "https://join.justzappit.xyz/g/v1#regression-test-secret"

    @MainActor private func fixture(
        stage: GroupInvite.Stage = .preview(nameHint: "Crew"),
        linkId: String? = "current"
    ) -> (TestStoreOf<GroupInvite>, PendingGroupInviteStore, String) {
        let pending = PendingGroupInviteStore(persistence: .inMemory())
        guard case .accepted(let token) = pending.put(Self.link) else { fatalError("invalid fixture") }
        var state = GroupInvite.State(token: token)
        state.stage = stage
        state.linkId = linkId
        state.isActive = true
        let store = TestStore(initialState: state) { GroupInvite() } withDependencies: {
            $0.pendingGroupInvites = pending
            $0.zappMessaging = .testValue
        }
        store.exhaustivity = .off
        return (store, pending, token)
    }

    @MainActor @Test func unrelatedUpdateCannotSpendAnUninspectedInvite() async {
        let (store, pending, token) = fixture(stage: .reading, linkId: nil)
        await store.send(.response(store.state.sessionID, .updated(
            ZMGroupJoinUpdate(linkId: "unrelated", status: .joined, conversationId: "wrong-room")
        )))
        #expect(store.state.stage == .reading)
        #expect(pending.link(for: token) == Self.link)
    }

    @MainActor @Test(arguments: [ZMGroupJoinStatus.full, .declined, .expired, .inactive, .cancelled])
    func historicalFailureDoesNotPreventANewAttempt(status: ZMGroupJoinStatus) async {
        let (store, pending, token) = fixture()
        await store.send(.response(store.state.sessionID, .updated(ZMGroupJoinUpdate(linkId: "current", status: status))))
        #expect(store.state.stage == .preview(nameHint: "Crew"))
        #expect(pending.link(for: token) == Self.link)
    }

    @MainActor @Test func previousScreenRepliesCannotSpendTheCurrentInviteEvenForTheSameLink() async {
        let (store, pending, token) = fixture(stage: .requesting(nameHint: "Crew"))
        let oldSession = UUID()
        await store.send(.response(oldSession, .joinAnswered(ZMGroupJoinResult(status: .requested, linkId: "current"))))
        await store.send(.response(oldSession, .inspectFailed))
        #expect(store.state.stage == .requesting(nameHint: "Crew"))
        #expect(pending.link(for: token) == Self.link)
    }

    @MainActor @Test func queuedRequestAdvancesToSentAndThenOwnerApprovalWithoutLosingItsName() async {
        let (store, pending, token) = fixture(stage: .requesting(nameHint: "Crew"))
        await store.send(.joinAnswered(ZMGroupJoinResult(status: .requested, linkId: "current", sent: false)))
        #expect(store.state.stage == .waiting(linkId: "current", nameHint: "Crew", progress: .queued))
        #expect(pending.link(for: token) == nil)
        await store.send(.updated(ZMGroupJoinUpdate(linkId: "current", status: .waiting, sent: true)))
        #expect(store.state.stage == .waiting(linkId: "current", nameHint: "Crew", progress: .sent))
        await store.send(.updated(ZMGroupJoinUpdate(linkId: "current", status: .waiting, sent: false)))
        #expect(store.state.stage == .waiting(linkId: "current", nameHint: "Crew", progress: .sent))
        await store.send(.updated(ZMGroupJoinUpdate(linkId: "current", status: .pendingApproval)))
        await store.send(.updated(ZMGroupJoinUpdate(linkId: "current", status: .waiting)))
        #expect(store.state.stage == .waiting(linkId: "current", nameHint: "Crew", progress: .withOwner))
        await store.finish()
    }

    @MainActor @Test func joinedIsNotOverwrittenByALateRequestReply() async {
        let (store, _, _) = fixture(stage: .requesting(nameHint: "Crew"))
        await store.send(.updated(ZMGroupJoinUpdate(linkId: "current", status: .joined, conversationId: "room")))
        await store.send(.joinAnswered(ZMGroupJoinResult(status: .requested, linkId: "current")))
        #expect(store.state.stage == .joined(conversationId: "room", nameHint: "Crew", alreadyMember: false))
    }

    @MainActor @Test func teardownCancelsAnInspectionThatIgnoresCancellation() async {
        let pending = PendingGroupInviteStore(persistence: .inMemory())
        guard case .accepted(let token) = pending.put(Self.link) else {
            Issue.record("invalid fixture")
            return
        }
        let started = SignalledRecords<Void>()
        let cancelled = SignalledRecords<Void>()
        let gate = ResumableGate()
        let store = TestStore(initialState: GroupInvite.State(token: token)) { GroupInvite() } withDependencies: {
            $0.pendingGroupInvites = pending
            $0.zappMessaging = .testValue
            $0.zappMessaging.inspectGroupLink = { _ in
                await withTaskCancellationHandler {
                    started.recordCall()
                    await gate.wait()
                    return ZMGroupLinkInspection(status: .ok, nameHint: "Late", linkId: "late")
                } onCancel: {
                    cancelled.recordCall()
                }
            }
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await started.countReached(1)
        await store.send(.teardown)
        await cancelled.countReached(1)
        gate.open()
        await store.finish()
        #expect(!store.state.isActive)
        #expect(store.state.stage == .reading)
        #expect(pending.link(for: token) == Self.link)
    }

    @MainActor
    @Test func inspectionRetriesOnceBeforeShowingThePreview() async {
        let pending = PendingGroupInviteStore(persistence: .inMemory())
        guard case .accepted(let token) = pending.put(Self.link) else {
            Issue.record("invalid fixture")
            return
        }
        let calls = SignalledRecords<String>()
        let store = TestStore(initialState: GroupInvite.State(token: token)) { GroupInvite() } withDependencies: {
            $0.pendingGroupInvites = pending
            $0.continuousClock = ImmediateClock()
            $0.zappMessaging.inspectGroupLink = { link in
                if calls.record(link) == 1 { throw ZMError.notInitialized }
                return ZMGroupLinkInspection(status: .ok, nameHint: "Crew", linkId: "current")
            }
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive {
            guard case .response(_, .inspected) = $0 else { return false }
            return true
        }
        #expect(store.state.stage == .preview(nameHint: "Crew"))
        #expect(calls.values == [Self.link, Self.link])
        #expect(pending.link(for: token) == Self.link)
        await store.send(.teardown)
        await store.finish()
    }

    @MainActor
    @Test func aFailedInspectionCanBeReopenedByTappingTheSameLink() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let pending = PendingGroupInviteStore(persistence: .inMemory())
            let calls = SignalledRecords<String>()
            var state = Root.State.initial
            state.appInitializationState = .initialized
            state.destinationState.destination = .home
            state.zappMessagingState.identity = ZMIdentity(publicKey: "guest", displayName: "Guest")
            state.$featureFlags.withLock { $0 = FeatureFlags(groupLinks: true) }
            let store = TestStore(initialState: state) { Root() } withDependencies: {
                $0.walletStorage = .noOp
                $0.pendingGroupInvites = pending
                $0.continuousClock = ImmediateClock()
                $0.zappMessaging.inspectGroupLink = { link in
                    if calls.record(link) <= 2 { throw ZMError.notInitialized }
                    return ZMGroupLinkInspection(status: .ok, nameHint: "Crew", linkId: "current")
                }
            }
            store.exhaustivity = .off
            await store.send(.groupInviteReceived(Self.link))
            await store.receive(\.groupInviteResumed)
            await store.receive {
                guard case .destination(.updateDestination) = $0 else { return false }
                return true
            }
            let token = store.state.groupInviteState.token
            await store.send(.groupInvite(.onAppear))
            await store.receive(\.groupInvite.delegate)
            await store.receive {
                guard case .destination(.updateDestination) = $0 else { return false }
                return true
            }
            #expect(store.state.destinationState.destination == .home)
            #expect(calls.values == [Self.link, Self.link])
            #expect(pending.newestToken() == token)

            await store.send(.groupInviteReceived(Self.link))
            await store.receive(\.groupInviteResumed)
            await store.receive {
                guard case .destination(.updateDestination) = $0 else { return false }
                return true
            }
            #expect(store.state.destinationState.destination == .groupInvite)
            #expect(store.state.groupInviteState.token == token)
            await store.send(.groupInvite(.onAppear))
            await store.receive {
                guard case .groupInvite(.response(_, .inspected)) = $0 else { return false }
                return true
            }
            #expect(store.state.groupInviteState.stage == .preview(nameHint: "Crew"))
            #expect(calls.values == [Self.link, Self.link, Self.link])
            await store.send(.groupInvite(.teardown))
            await store.finish()
        }
    }

    @MainActor
    @Test func aRepeatTapDoesNotReplaceAnActivePreview() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let pending = PendingGroupInviteStore(persistence: .inMemory())
            guard case .accepted(let token) = pending.put(Self.link) else {
                Issue.record("invalid fixture")
                return
            }
            var state = Root.State.initial
            state.destinationState.destination = .groupInvite
            state.groupInviteState = GroupInvite.State(token: token)
            state.groupInviteState.stage = .preview(nameHint: "Crew")
            state.groupInviteState.isActive = true
            state.$featureFlags.withLock { $0 = FeatureFlags(groupLinks: true) }
            let sessionID = state.groupInviteState.sessionID
            let store = TestStore(initialState: state) { Root() } withDependencies: {
                $0.walletStorage = .noOp
                $0.pendingGroupInvites = pending
            }
            await store.send(.groupInviteReceived(Self.link))
            #expect(store.state.groupInviteState.token == token)
            #expect(store.state.groupInviteState.sessionID == sessionID)
            #expect(store.state.groupInviteState.stage == .preview(nameHint: "Crew"))
            await store.finish()
        }
    }
}
