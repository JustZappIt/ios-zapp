// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import ZappMessaging

/// One tapped invite link, from reading it to the answer.
///
/// The link is a bearer secret, so only its intake token is held here: the raw link is fetched
/// from the store for the one call that needs it, and deleted the moment the SDK holds the
/// request. Mirrors Android's `GroupInviteMachine` transition for transition, because a joiner
/// who taps the same link on either phone has to see the same thing.
@Reducer
struct GroupInvite {
    enum Stage: Equatable {
        case reading
        case preview(nameHint: String?)
        case requesting(nameHint: String?)
        /// The request is with the owner. `withOwner` means it waits on a person, not a device.
        case waiting(linkId: String, withOwner: Bool)
        case joined(conversationId: String?, nameHint: String?, alreadyMember: Bool)
        case failed(Failure)
        /// The build does not offer group links yet.
        case comingSoon
    }

    enum Failure: Equatable {
        case unreadable
        case expired
        case needsUpdate
        case inactive
        case full
        case declined
    }

    @ObservableState
    struct State: Equatable {
        /// The intake token this screen was opened with. Nil for a link the store refused.
        var token: String?
        var comingSoon = false
        var stage: Stage = .reading
        /// The last request never left the device. The link is kept, so it can be tried again.
        var sendFailed = false

        var linkId: String?

        init(token: String? = nil, comingSoon: Bool = false) {
            self.token = token
            self.comingSoon = comingSoon
        }
    }

    enum Action {
        case onAppear
        case teardown
        case inspected(ZMGroupLinkInspection)
        case inspectFailed
        case statusRefreshed([ZMGroupJoinUpdate])
        case joinTapped
        case joinAnswered(ZMGroupJoinResult)
        case joinFailed
        case notNowTapped
        case cancelTapped
        case updated(ZMGroupJoinUpdate)
        case openGroupTapped(String)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case dismiss
            case openConversation(String)
        }
    }

    private enum CancelId {
        case updates
    }

    @Dependency(\.pendingGroupInvites) var pendingGroupInvites
    @Dependency(\.zappMessaging) var zappMessaging

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                if state.comingSoon {
                    state.stage = .comingSoon
                    return .none
                }
                guard let token = state.token else {
                    state.stage = .failed(.unreadable)
                    return .none
                }
                guard let link = pendingGroupInvites.link(for: token) else {
                    // The invite lapsed, or was answered on another screen. Nothing to show.
                    return .send(.delegate(.dismiss))
                }
                return .merge(
                    .publisher {
                        zappMessaging.groupJoinUpdatesStream().map(Action.updated)
                    }
                    .cancellable(id: CancelId.updates, cancelInFlight: true),
                    .run { send in
                        // Reading is local, so a failure means the worklet is not up yet, not that
                        // the link is bad. The link is kept either way.
                        do {
                            await send(.inspected(try await zappMessaging.inspectGroupLink(link)))
                        } catch {
                            await send(.inspectFailed)
                        }
                    }
                )

            case .teardown:
                return .cancel(id: CancelId.updates)

            case .inspected(let inspection):
                state.linkId = inspection.linkId
                switch inspection.status {
                case .ok:
                    state.stage = .preview(nameHint: inspection.nameHint)
                case .expired:
                    state.stage = .failed(.expired)
                    return .merge(dropLink(&state), refreshStatus(state))
                case .malformed:
                    state.stage = .failed(.unreadable)
                    return .merge(dropLink(&state), refreshStatus(state))
                case .unsupportedVersion, .newerFormat:
                    state.stage = .failed(.needsUpdate)
                    return .merge(dropLink(&state), refreshStatus(state))
                }
                return refreshStatus(state)

            case .inspectFailed:
                return .send(.delegate(.dismiss))

            // A request an earlier tap already made, which the SDK knows about and this screen
            // does not.
            case .statusRefreshed(let updates):
                guard let linkId = state.linkId,
                      let update = updates.first(where: { $0.linkId == linkId }) else {
                    return .none
                }
                return .send(.updated(update))

            case .joinTapped:
                guard let token = state.token, let link = pendingGroupInvites.link(for: token) else {
                    return .send(.delegate(.dismiss))
                }
                state.sendFailed = false
                state.stage = .requesting(nameHint: state.stage.nameHint)
                return .run { send in
                    do {
                        await send(.joinAnswered(try await zappMessaging.joinGroupViaLink(link)))
                    } catch {
                        await send(.joinFailed)
                    }
                }

            case .joinAnswered(let result):
                if let linkId = result.linkId { state.linkId = linkId }
                switch result.status {
                case .requested, .alreadyRequested:
                    state.stage = .waiting(linkId: result.linkId ?? state.linkId ?? "", withOwner: false)
                case .alreadyMember:
                    state.stage = .joined(
                        conversationId: result.conversationId,
                        nameHint: state.stage.nameHint,
                        alreadyMember: true
                    )
                case .expired:
                    state.stage = .failed(.expired)
                case .malformed:
                    state.stage = .failed(.unreadable)
                case .unsupportedVersion, .newerFormat:
                    state.stage = .failed(.needsUpdate)
                }
                // The SDK holds the request now, so the secret has no reason to outlive it.
                return .merge(dropLink(&state), refreshStatus(state))

            case .joinFailed:
                // Nothing left the device, so the link stays and the screen says so.
                state.sendFailed = true
                state.stage = .preview(nameHint: state.stage.nameHint)
                return .none

            case .updated(let update):
                guard state.linkId == nil || update.linkId == state.linkId else { return .none }
                state.linkId = update.linkId
                switch update.status {
                case .waiting:
                    state.stage = .waiting(linkId: update.linkId, withOwner: false)
                case .pendingApproval:
                    state.stage = .waiting(linkId: update.linkId, withOwner: true)
                case .joined:
                    state.stage = .joined(
                        conversationId: update.conversationId,
                        nameHint: update.nameHint ?? state.stage.nameHint,
                        alreadyMember: false
                    )
                case .inactive:
                    state.stage = .failed(.inactive)
                case .expired:
                    state.stage = .failed(.expired)
                case .full:
                    state.stage = .failed(.full)
                case .declined:
                    state.stage = .failed(.declined)
                case .cancelled:
                    return .send(.delegate(.dismiss))
                case .unknown:
                    return .none
                }
                return dropLink(&state)

            case .notNowTapped:
                return .merge(dropLink(&state), .send(.delegate(.dismiss)))

            case .cancelTapped:
                guard case .waiting(let linkId, _) = state.stage else {
                    return .send(.delegate(.dismiss))
                }
                return .run { send in
                    _ = try? await zappMessaging.cancelGroupJoin(linkId)
                    await send(.delegate(.dismiss))
                }

            case .openGroupTapped(let conversationId):
                return .send(.delegate(.openConversation(conversationId)))

            case .delegate:
                return .none
            }
        }
    }

    private func dropLink(_ state: inout State) -> Effect<Action> {
        guard let token = state.token else { return .none }
        state.token = nil
        pendingGroupInvites.remove(token: token)
        return .none
    }

    private func refreshStatus(_ state: State) -> Effect<Action> {
        guard state.linkId != nil else { return .none }
        return .run { send in
            if let updates = try? await zappMessaging.groupJoinStatus() {
                await send(.statusRefreshed(updates))
            }
        }
    }
}

extension GroupInvite.Stage {
    /// The group's name, when the link carried one, through every stage that can still show it.
    var nameHint: String? {
        switch self {
        case .preview(let name), .requesting(let name): return name
        case .joined(_, let name, _): return name
        case .reading, .waiting, .failed, .comingSoon: return nil
        }
    }
}
