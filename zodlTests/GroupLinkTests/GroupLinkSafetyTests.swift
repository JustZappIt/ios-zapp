// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(1)))
struct GroupLinkSafetyTests {
    private static let secret = "must-not-appear-in-logs"
    private static let link = "https://join.justzappit.xyz/g/v1#\(secret)"

    @Test func ownerStateAndActionsRedactBearerLinksInTCADumps() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let info = ZMGroupLinkInfo(conversationId: "room", state: .active, link: Self.link)
            var state = GroupLink.State(conversationId: "room")
            state.info = info
            state.linkToShare = Self.link
            let descriptions = [
                String(customDumping: state),
                String(customDumping: GroupLink.Action.linkLoaded(info)),
                diff(GroupLink.State(conversationId: "room"), state) ?? ""
            ]
            for description in descriptions {
                #expect(!description.contains(Self.secret))
            }
            #expect(String(customDumping: state).contains("redacted"))
        }
    }

    @Test func rootRedactsIntakeBeforeDeeplinkClassification() throws {
        let url = try #require(URL(string: Self.link))
        let actions: [Root.Action] = [
            .groupInviteReceived(Self.link),
            .destination(.deeplink(url))
        ]
        for action in actions {
            let description = String(customDumping: action)
            #expect(!description.contains(Self.secret))
            #expect(description.contains("redacted"))
        }
        #expect(String(customDumping: Root.Action.groupInviteResumePending).contains("groupInviteResumePending"))
    }

    @Test(arguments: [1, 2, 6, 8, 29])
    func expiryReportsRemainingDaysInsteadOfTheNextPreset(days: Int) {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let now = Date(timeIntervalSince1970: 1_000)
            var state = GroupLink.State(conversationId: "room")
            state.info = ZMGroupLinkInfo(
                conversationId: "room", state: .active,
                expiresAt: now.addingTimeInterval(Double(days) * GroupLink.day - 1)
            )
            #expect(state.remainingDays(now: now) == days)
        }
    }

    @MainActor @Test func withdrawalStreamRefreshesTheOwnersPendingRequests() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let withdrawn = PassthroughSubject<String, Never>()
            let subscription = SignalledRecords<Void>()
            let calls = SignalledRecords<String>()
            let request = ZMGroupJoinApprovalRequest(
                conversationId: "room", joinerKey: "joiner", joinerName: "Guest"
            )
            let store = TestStore(initialState: GroupLink.State(conversationId: "room")) {
                GroupLink()
            } withDependencies: {
                $0.zappMessaging.groupLink = { id in ZMGroupLinkInfo(conversationId: id, state: .active) }
                $0.zappMessaging.groupJoinRequests = { id in
                    calls.record(id) == 1 ? [request] : []
                }
                $0.zappMessaging.groupJoinRequestWithdrawnStream = {
                    withdrawn.handleEvents(receiveSubscription: { _ in subscription.recordCall() }).eraseToAnyPublisher()
                }
            }
            store.exhaustivity = .off
            await store.send(.onAppear)
            await store.receive(\.requestsLoaded)
            #expect(store.state.requests == [request])
            await subscription.countReached(1)
            withdrawn.send("room")
            await store.receive(\.requestWithdrawn)
            await store.receive(\.requestsLoaded)
            #expect(store.state.requests.isEmpty)
            #expect(calls.values == ["room", "room"])
            await store.send(.onDisappear)
            await store.finish()
        }
    }

    @MainActor @Test func removalWaitsForSafetyContextAndResetsTheLiveLink() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let member = GroupMember(publicKey: "guest", name: "Guest", isOwner: false)
            var state = GroupInfo.State(conversation: ZMConversation(
                id: "room", type: .group, participantIds: ["owner", "guest"], displayName: "Crew", isOwner: true
            ))
            state.removing = GroupInfo.State.RemoveDraft(member: member)
            let removals = SignalledRecords<Bool>()
            let store = TestStore(initialState: state) { GroupInfo() } withDependencies: {
                $0.zappMessaging.removeMember = { _, _, reset in
                    removals.record(reset)
                    return ZMRemoveMemberResult(participants: ["owner"], olderMemberCount: 2)
                }
                $0.zappMessaging.refreshConversations = { }
            }
            store.exhaustivity = .off
            await store.send(.removeConfirmed)
            await store.finish()
            #expect(removals.isEmpty)
            #expect(store.state.removing?.isBusy == false)
            await store.send(.removeContextLoaded(publicKey: "guest", olderMemberCount: 2, canResetLink: true))
            #expect(store.state.removing?.olderMemberCount == 2)
            await store.send(.removeConfirmed)
            await store.receive(\.removeFinished)
            #expect(removals.values == [true])
            #expect(store.state.removing == nil)
            await store.finish()
        }
    }

    @MainActor @Test func failedSafetyReadClosesRemovalWithoutRemovingAnyone() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = GroupInfo.State(conversation: ZMConversation(
                id: "room", type: .group, participantIds: ["owner", "guest"], displayName: "Crew", isOwner: true
            ))
            state.removing = GroupInfo.State.RemoveDraft(member: GroupMember(publicKey: "guest", name: "Guest", isOwner: false))
            let store = TestStore(initialState: state) { GroupInfo() }
            store.exhaustivity = .off
            await store.send(.removeContextFailed(publicKey: "guest"))
            await store.send(.removeConfirmed)
            #expect(store.state.removing == nil)
            #expect(store.state.didFail)
            await store.finish()
        }
    }

    @MainActor @Test(arguments: [false, true])
    func dismissalChoosesTheDestinationForTheWallet(hasWallet: Bool) async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .groupInvite
            state.appInitializationState = hasWallet ? .initialized : .keysMissing
            let store = TestStore(initialState: state) { Root() }
            store.exhaustivity = .off
            await store.send(.groupInvite(.delegate(.dismiss)))
            await store.receive(\.destination.updateDestination)
            #expect(store.state.destinationState.destination == (hasWallet ? .home : .onboarding))
            await store.finish()
        }
    }

    @MainActor @Test func restoredIdentityReassertsThePersistedBlocklist() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let blockedKey = String(repeating: "a", count: 64)
            var state = Root.State.initial
            state.$chatContacts.withLock {
                $0.contacts.append(ChatContact(publicKey: blockedKey, name: "Blocked", isBlocked: true))
            }
            let pushed = SignalledRecords<Set<String>>()
            let store = TestStore(initialState: state) { Root() } withDependencies: {
                $0.zappMessaging.setBlockedKeys = { pushed.record($0) }
            }
            store.exhaustivity = .off
            var messaging = ZappMessagingState()
            messaging.identity = ZMIdentity(publicKey: "owner", displayName: "Owner")
            messaging.phase = .ready
            await store.send(.zappMessagingStateChanged(messaging))
            #expect(pushed.values == [[blockedKey]])
            await store.receive(\.groupInviteResumePending)
            await store.finish()
        }
    }
}
