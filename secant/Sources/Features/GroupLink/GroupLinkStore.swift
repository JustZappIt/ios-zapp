// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import ZappMessaging

/// The owner's controls for one group's invite link.
///
/// Every control is one SDK call that answers with the whole link record, so the screen never has
/// to guess what changed. A call that fails leaves the last known record on screen and says so,
/// because a control that silently does nothing is how an owner ends up believing a link is off.
@Reducer
struct GroupLink {
    /// The windows the owner can pick. A link expires relative to the moment it is set, so the row
    /// reads back as the choice rather than as a date nobody typed.
    static let expiryChoices: [Int?] = [nil, 1, 7, 30]
    static let limitChoices: [Int?] = [nil, 10, 25, 50, 100]
    static let day: TimeInterval = 24 * 60 * 60
    static let rateReason = "rate"

    enum Picker: Equatable {
        case expiry
        case limit
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        var conversationId = ""
        /// Only the creator can admit anyone, so for everyone else the screen says so and stops.
        var isOwner = true

        /// Nil until the first read lands.
        var info: ZMGroupLinkInfo?
        var requests: [ZMGroupJoinApprovalRequest] = []

        var isBusy = false
        var didFail = false
        /// Approving ran the checks again and the group is full.
        var isFull = false
        var isCopied = false
        var picker: Picker?
        var isConfirmingReset = false
        /// Non-nil while the share sheet is up. The link, and nothing around it.
        var linkToShare: String?

        var requestsCancelId = UUID()

        var isActive: Bool { info?.state == .active }
        var link: String? { isActive ? info?.link : nil }

        var noticeText: String? {
            if info?.state == .off { return String(localizable: .groupLinkOffNote) }
            if info?.approvalReason == GroupLink.rateReason { return String(localizable: .groupLinkPaused) }
            return nil
        }

        var errorText: String? {
            if didFail { return String(localizable: .groupLinkActionFailed) }
            if isFull { return String(localizable: .groupInviteFull) }
            return nil
        }

        var isLoading: Bool { info == nil && !didFail }

        /// What is left of the link's life, in days, rounded up to the window the owner picked.
        /// Nil means it never expires, zero means it already has.
        func remainingDays(now: Date) -> Int? {
            guard let expiresAt = info?.expiresAt else { return nil }
            let remaining = expiresAt.timeIntervalSince(now)
            if remaining <= 0 { return 0 }
            let days = Int((remaining / GroupLink.day).rounded(.up))
            return GroupLink.expiryChoices.compactMap { $0 }.first { days <= $0 } ?? days
        }

        func expiryText(now: Date) -> String {
            switch remainingDays(now: now) {
            case .none: return String(localizable: .groupLinkExpiryNever)
            case .some(0): return String(localizable: .groupLinkExpired)
            case .some(1): return String(localizable: .groupLinkExpiryOneDay)
            case .some(let days): return String(localizable: .groupLinkExpiryDaysFmt("\(days)"))
            }
        }

        static func limitText(_ maxJoins: Int?) -> String {
            guard let maxJoins else { return String(localizable: .groupLinkLimitNone) }
            return String(localizable: .groupLinkLimitPeopleFmt("\(maxJoins)"))
        }

        /// The owner's own name for a joiner, when they are already a contact.
        func contactName(for joinerKey: String) -> String? {
            let name = chatContacts.contact(for: joinerKey)?.name
            return (name?.isEmpty == false) ? name : nil
        }

        init(conversationId: String = "", isOwner: Bool = true) {
            self.conversationId = conversationId
            self.isOwner = isOwner
        }

        static let initial = State()
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backTapped
        case linkLoaded(ZMGroupLinkInfo)
        case loadFailed
        case requestsLoaded([ZMGroupJoinApprovalRequest])
        case requestReceived(ZMGroupJoinApprovalRequest)
        case retryTapped
        case turnOnTapped
        case turnOffTapped
        case resetTapped
        case resetConfirmed
        case resetDismissed
        case pickerOpened(Picker)
        case pickerDismissed
        case expiryPicked(Int?)
        case limitPicked(Int?)
        case nameToggled
        case approvalToggled
        case copyTapped
        case copyFeedbackElapsed
        case shareTapped
        case shareFinished
        case approveTapped(String)
        case declineTapped(String)
        case answerFinished(admitted: Bool)
        case actionFailed
    }

    private enum CancelId {
        case copyFeedback
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.isOwner else { return .none }
                return .merge(
                    load(state.conversationId),
                    .publisher {
                        zappMessaging.groupJoinRequestStream()
                            .filter { [id = state.conversationId] in $0.conversationId == id }
                            .map(Action.requestReceived)
                    }
                    .cancellable(id: state.requestsCancelId, cancelInFlight: true)
                )

            case .onDisappear:
                return .merge(.cancel(id: state.requestsCancelId), .cancel(id: CancelId.copyFeedback))

            case .backTapped:
                return .none

            case .linkLoaded(let info):
                state.info = info
                state.didFail = false
                state.isBusy = false
                return .none

            case .loadFailed:
                state.isBusy = false
                state.didFail = true
                return .none

            case .requestsLoaded(let requests):
                state.requests = requests
                return .none

            case .requestReceived:
                return loadRequests(state.conversationId)

            case .retryTapped:
                state.didFail = false
                return load(state.conversationId)

            case .turnOnTapped:
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.enableGroupLink(id, ZMGroupLinkOptions())
                }

            case .turnOffTapped:
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.disableGroupLink(id)
                }

            case .resetTapped:
                state.isConfirmingReset = true
                return .none

            case .resetDismissed:
                state.isConfirmingReset = false
                return .none

            case .resetConfirmed:
                state.isConfirmingReset = false
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.resetGroupLink(id)
                }

            case .pickerOpened(let picker):
                state.picker = picker
                return .none

            case .pickerDismissed:
                state.picker = nil
                return .none

            case .expiryPicked(let days):
                state.picker = nil
                let options = days.map {
                    ZMGroupLinkOptions(expiresAt: date.now().addingTimeInterval(Double($0) * GroupLink.day))
                } ?? ZMGroupLinkOptions(clearExpiry: true)
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.updateGroupLink(id, options)
                }

            case .limitPicked(let maxJoins):
                state.picker = nil
                let options = maxJoins.map { ZMGroupLinkOptions(maxJoins: $0) }
                    ?? ZMGroupLinkOptions(clearMaxJoins: true)
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.updateGroupLink(id, options)
                }

            case .nameToggled:
                let includeName = !(state.info?.includeName ?? true)
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.updateGroupLink(id, ZMGroupLinkOptions(includeName: includeName))
                }

            case .approvalToggled:
                let approval: ZMGroupLinkApproval = state.info?.approval == .owner ? .auto : .owner
                return call(&state) { [id = state.conversationId] in
                    try await zappMessaging.updateGroupLink(id, ZMGroupLinkOptions(approval: approval))
                }

            case .copyTapped:
                guard let link = state.link else { return .none }
                // Sensitive: local only and short lived, so a bearer secret does not ride the
                // Universal Clipboard to another device.
                pasteboard.setSensitiveString(RedactableString(link))
                state.isCopied = true
                return .run { send in
                    try await clock.sleep(for: .seconds(2))
                    await send(.copyFeedbackElapsed)
                }
                .cancellable(id: CancelId.copyFeedback, cancelInFlight: true)

            case .copyFeedbackElapsed:
                state.isCopied = false
                return .none

            case .shareTapped:
                state.linkToShare = state.link
                return .none

            case .shareFinished:
                state.linkToShare = nil
                return .none

            case .approveTapped(let joinerKey):
                guard !state.isBusy else { return .none }
                state.isBusy = true
                state.didFail = false
                state.isFull = false
                return .run { [id = state.conversationId] send in
                    let admitted = try await zappMessaging.approveGroupJoinRequest(id, joinerKey)
                    await send(.answerFinished(admitted: admitted))
                } catch: { error, send in
                    LoggerProxy.error("Group link failed to approve a request: \(error)")
                    await send(.actionFailed)
                }

            case .declineTapped(let joinerKey):
                guard !state.isBusy else { return .none }
                state.isBusy = true
                state.didFail = false
                state.isFull = false
                return .run { [id = state.conversationId] send in
                    try await zappMessaging.declineGroupJoinRequest(id, joinerKey)
                    await send(.answerFinished(admitted: true))
                } catch: { error, send in
                    LoggerProxy.error("Group link failed to decline a request: \(error)")
                    await send(.actionFailed)
                }

            // Either way the request is gone from the owner's device, so the list and the record
            // are read again rather than patched.
            case .answerFinished(let admitted):
                state.isBusy = false
                state.isFull = !admitted
                return load(state.conversationId)

            case .actionFailed:
                state.isBusy = false
                state.didFail = true
                return .none
            }
        }
    }

    /// One control, one call. A second tap while a call is in flight is ignored.
    private func call(
        _ state: inout State,
        _ operation: @escaping @Sendable () async throws -> ZMGroupLinkInfo
    ) -> Effect<Action> {
        guard !state.isBusy else { return .none }
        state.isBusy = true
        state.didFail = false
        state.isFull = false
        return .run { send in
            await send(.linkLoaded(try await operation()))
        } catch: { error, send in
            LoggerProxy.error("Group link control failed: \(error)")
            await send(.actionFailed)
        }
    }

    private func load(_ conversationId: String) -> Effect<Action> {
        .merge(
            .run { send in
                await send(.linkLoaded(try await zappMessaging.groupLink(conversationId)))
            } catch: { error, send in
                LoggerProxy.error("Group link failed to load: \(error)")
                await send(.loadFailed)
            },
            loadRequests(conversationId)
        )
    }

    private func loadRequests(_ conversationId: String) -> Effect<Action> {
        .run { send in
            if let requests = try? await zappMessaging.groupJoinRequests(conversationId) {
                await send(.requestsLoaded(requests))
            }
        }
    }
}
