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
    enum WaitingStage: Equatable {
        case queued
        case sent
        case withOwner
    }

    enum Stage: Equatable {
        case reading
        case preview(nameHint: String?)
        case requesting(nameHint: String?)
        case waiting(linkId: String, nameHint: String?, progress: WaitingStage)
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
        // Root reuses the reducer across previews. Every reply belongs to one screen lifetime,
        // even when the underlying SDK request ignores Swift task cancellation.
        var sessionID = UUID()
        var isActive = false
        var statusRefreshID: UUID?

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
        case statusRefreshed(UUID, [ZMGroupJoinUpdate])
        indirect case response(UUID, Action)
        case joinTapped
        case joinAnswered(ZMGroupJoinResult)
        case joinFailed
        case notNowTapped
        case cancelTapped
        case cancelFinished
        case updated(ZMGroupJoinUpdate)
        case openGroupTapped(String)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case dismiss
            case openConversation(String)
        }
    }

    private struct StatusCancelId: Hashable {
        let sessionID: UUID
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.pendingGroupInvites) var pendingGroupInvites
    @Dependency(\.zappMessaging) var zappMessaging

    var body: some Reducer<State, Action> {
        Reduce { state, receivedAction in
            let action: Action
            if case .response(let sessionID, let response) = receivedAction {
                guard state.isActive, state.sessionID == sessionID else { return .none }
                action = response
            } else {
                action = receivedAction
            }
            switch action {
            case .onAppear:
                guard !state.isActive else { return .none }
                state.isActive = true
                if state.comingSoon {
                    state.stage = .comingSoon
                    return .none
                }
                // Reappearing after a join keeps the SDK-owned request, even though its raw
                // link has already been deleted.
                if state.stage != .reading {
                    return .merge(observeUpdates(state.sessionID), refreshStatus(&state))
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
                    observeUpdates(state.sessionID),
                    .run { [sessionID = state.sessionID] send in
                        // Reading is local. An unavailable worklet must not spend the link.
                        do {
                            let inspection = try await inspect(link)
                            guard !Task.isCancelled else { return }
                            await send(.response(sessionID, .inspected(inspection)))
                        } catch {
                            guard !Task.isCancelled else { return }
                            await send(.response(sessionID, .inspectFailed))
                        }
                    }
                    .cancellable(id: state.sessionID)
                )

            case .teardown:
                return stop(&state)

            case .inspected(let inspection):
                guard state.stage == .reading else { return .none }
                state.linkId = inspection.linkId
                switch inspection.status {
                case .ok:
                    state.stage = .preview(nameHint: inspection.nameHint)
                case .expired:
                    state.stage = .failed(.expired)
                    return dropLink(&state)
                case .malformed:
                    state.stage = .failed(.unreadable)
                    return dropLink(&state)
                case .unsupportedVersion, .newerFormat:
                    state.stage = .failed(.needsUpdate)
                    return dropLink(&state)
                }
                return refreshStatus(&state)

            case .inspectFailed:
                return .send(.delegate(.dismiss))

            // A request an earlier tap already made, which the SDK knows about and this screen
            // does not.
            case let .statusRefreshed(refreshID, updates):
                guard state.statusRefreshID == refreshID else { return .none }
                guard let linkId = state.linkId,
                    let update = updates.first(where: { $0.linkId == linkId }) else {
                    return .none
                }
                return .send(.response(state.sessionID, .updated(update)))

            case .joinTapped:
                guard case .preview = state.stage else { return .none }
                state.statusRefreshID = nil
                guard let token = state.token, let link = pendingGroupInvites.link(for: token) else {
                    return .send(.delegate(.dismiss))
                }
                state.sendFailed = false
                state.stage = .requesting(nameHint: state.stage.nameHint)
                return .run { [sessionID = state.sessionID] send in
                    do {
                        let result = try await zappMessaging.joinGroupViaLink(link)
                        guard !Task.isCancelled else { return }
                        await send(.response(sessionID, .joinAnswered(result)))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.response(sessionID, .joinFailed))
                    }
                }
                .cancellable(id: state.sessionID)

            case .joinAnswered(let result):
                guard case .requesting = state.stage,
                    result.linkId == nil || result.linkId == state.linkId else { return .none }
                if let linkId = result.linkId { state.linkId = linkId }
                switch result.status {
                case .requested, .alreadyRequested:
                    guard let linkId = state.linkId else {
                        state.stage = .failed(.unreadable)
                        return dropLink(&state)
                    }
                    state.stage = .waiting(linkId: linkId, nameHint: state.stage.nameHint, progress: result.sent ? .sent : .queued)
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
                return .merge(dropLink(&state), refreshStatus(&state))

            case .joinFailed:
                guard case .requesting = state.stage else { return .none }
                // Nothing left the device, so the link stays and the screen says so.
                state.sendFailed = true
                state.stage = .preview(nameHint: state.stage.nameHint)
                return .none

            case .updated(let update):
                guard let linkId = state.linkId, update.linkId == linkId else { return .none }
                let alreadyMember: Bool
                switch state.stage {
                case .preview:
                    // Terminal history belongs to an earlier attempt, not this fresh tap.
                    guard update.status.isWaiting || update.status == .joined else { return .none }
                    alreadyMember = update.status == .joined
                case .requesting, .waiting:
                    alreadyMember = false
                case .reading, .joined, .failed, .comingSoon:
                    return .none
                }
                switch update.status {
                case .waiting:
                    // A status read started before the owner's acknowledgement can arrive last.
                    if case .waiting(_, _, .withOwner) = state.stage { return .none }
                    if case .waiting(_, _, .sent) = state.stage, !update.sent { return .none }
                    state.stage = .waiting(
                        linkId: update.linkId,
                        nameHint: update.nameHint ?? state.stage.nameHint,
                        progress: update.sent ? .sent : .queued
                    )
                case .pendingApproval:
                    state.stage = .waiting(
                        linkId: update.linkId, nameHint: update.nameHint ?? state.stage.nameHint, progress: .withOwner
                    )
                case .joined:
                    state.stage = .joined(
                        conversationId: update.conversationId,
                        nameHint: update.nameHint ?? state.stage.nameHint,
                        alreadyMember: alreadyMember
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
                guard case .waiting(let linkId, _, _) = state.stage else {
                    return .send(.delegate(.dismiss))
                }
                return .run { [sessionID = state.sessionID] send in
                    _ = try? await zappMessaging.cancelGroupJoin(linkId)
                    guard !Task.isCancelled else { return }
                    await send(.response(sessionID, .cancelFinished))
                }
                .cancellable(id: state.sessionID)

            case .cancelFinished:
                return .send(.delegate(.dismiss))

            case .openGroupTapped(let conversationId):
                return .send(.delegate(.openConversation(conversationId)))

            case .delegate:
                return stop(&state)

            case .response:
                return .none
            }
        }
    }

    private func inspect(_ link: String) async throws -> ZMGroupLinkInspection {
        do {
            return try await zappMessaging.inspectGroupLink(link)
        } catch {
            // As on Android, give a starting worklet one retry. A transient local read
            // failure must not spend the link or contact the group owner.
            try await clock.sleep(for: .milliseconds(1_500))
            try Task.checkCancellation()
            return try await zappMessaging.inspectGroupLink(link)
        }
    }

    private func dropLink(_ state: inout State) -> Effect<Action> {
        guard let token = state.token else { return .none }
        state.token = nil
        pendingGroupInvites.remove(token: token)
        return .none
    }

    private func stop(_ state: inout State) -> Effect<Action> {
        let sessionID = state.sessionID
        state.isActive = false
        state.statusRefreshID = nil
        state.sessionID = UUID()
        return .merge(.cancel(id: sessionID), .cancel(id: StatusCancelId(sessionID: sessionID)))
    }

    private func observeUpdates(_ sessionID: UUID) -> Effect<Action> {
        .publisher {
            zappMessaging.groupJoinUpdatesStream().map { Action.response(sessionID, .updated($0)) }
        }
        .cancellable(id: sessionID)
    }

    private func refreshStatus(_ state: inout State) -> Effect<Action> {
        guard state.linkId != nil else { return .none }
        let refreshID = UUID()
        state.statusRefreshID = refreshID
        return .run { [sessionID = state.sessionID] send in
            if let updates = try? await zappMessaging.groupJoinStatus() {
                guard !Task.isCancelled else { return }
                await send(.response(sessionID, .statusRefreshed(refreshID, updates)))
            }
        }
        .cancellable(id: StatusCancelId(sessionID: state.sessionID), cancelInFlight: true)
    }
}

extension GroupInvite.Stage {
    /// The group's name, when the link carried one, through every stage that can still show it.
    var nameHint: String? {
        switch self {
        case .preview(let name), .requesting(let name): return name
        case .joined(_, let name, _), .waiting(_, let name, _): return name
        case .reading, .failed, .comingSoon: return nil
        }
    }
}
