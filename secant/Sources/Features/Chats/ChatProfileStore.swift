//
//  ChatProfileStore.swift
//  Zapp
//
//  Your own chat identity: the display name peers see, the key they need to reach you,
//  and the two privacy switches.
//
//  Mirrors Android's ChatProfileVM, minus its secret-reveal surfaces (seed phrase, p2p
//  wallet key) and identity delete — neither has an iOS seam yet.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@Reducer
struct ChatProfile {
    @ObservableState
    struct State: Equatable {
        var messagingCancelId = UUID()

        /// The edited field. Sanitized on every keystroke, so it is always a candidate name.
        var displayName = ""

        /// What the worklet has actually persisted. The baseline for "changed", and the value the
        /// field is re-seeded from — never assumed to satisfy `UsernameRules`, since it was written
        /// by whatever version of the app created the identity.
        var savedDisplayName = ""

        var publicKey = ""
        var isSaving = false
        var saveFailed = false
        var didCopy = false

        var readReceiptsEnabled = true
        var presenceVisible = true

        /// A privacy call is in flight. The stream still carries the OLD value until the worklet
        /// acknowledges, so an unrelated emission (a peer count tick) would otherwise snap the
        /// optimistic toggle back mid-flight.
        var isReadReceiptsBusy = false
        var isPresenceBusy = false

        var isNameValid: Bool { UsernameRules.isValid(displayName) }
        var isNameChanged: Bool { displayName != savedDisplayName }
        var canSave: Bool { isNameValid && isNameChanged && !isSaving }
        var hasPublicKey: Bool { !publicKey.isEmpty }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case messagingStateChanged(ZappMessagingState)
        case displayNameChanged(String)
        case saveTapped
        case saveSucceeded(String)
        case saveFailed
        case copyPublicKeyTapped
        case copyIndicatorExpired
        case readReceiptsToggled
        case readReceiptsFinished(Bool)
        case presenceToggled
        case presenceFinished(Bool)
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    private enum CancelID { case copyIndicator }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                seed(&state, from: zappMessaging.latestState())

                return .publisher {
                    zappMessaging.stateStream()
                        .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                        .map(Action.messagingStateChanged)
                }
                .cancellable(id: state.messagingCancelId, cancelInFlight: true)

            case .onDisappear:
                return .merge(
                    .cancel(id: state.messagingCancelId),
                    .cancel(id: CancelID.copyIndicator)
                )

            case .messagingStateChanged(let messagingState):
                seed(&state, from: messagingState)
                return .none

            case .displayNameChanged(let value):
                state.displayName = UsernameRules.sanitize(value)
                state.saveFailed = false
                return .none

            case .saveTapped:
                guard state.canSave else { return .none }

                let name = state.displayName
                state.isSaving = true
                state.saveFailed = false

                // The SDK only adopts the name once the worklet echoes it back, so a throw means
                // nothing persisted: the field stays dirty and the user keeps their edit.
                return .run { send in
                    do {
                        try await zappMessaging.updateDisplayName(name)
                        await send(.saveSucceeded(name))
                    } catch {
                        LoggerProxy.error("ChatProfile: updateDisplayName failed: \(error)")
                        await send(.saveFailed)
                    }
                }

            case .saveSucceeded(let name):
                state.isSaving = false
                state.savedDisplayName = name
                state.displayName = name
                return .none

            case .saveFailed:
                state.isSaving = false
                state.saveFailed = true
                return .none

            case .copyPublicKeyTapped:
                guard state.hasPublicKey else { return .none }

                pasteboard.setString(RedactableString(state.publicKey))
                state.didCopy = true

                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyIndicatorExpired)
                }
                .cancellable(id: CancelID.copyIndicator, cancelInFlight: true)

            case .copyIndicatorExpired:
                state.didCopy = false
                return .none

            case .readReceiptsToggled:
                guard !state.isReadReceiptsBusy else { return .none }

                let previous = state.readReceiptsEnabled
                let next = !previous
                state.readReceiptsEnabled = next
                state.isReadReceiptsBusy = true

                // A privacy toggle that shows "off" while the worklet still emits receipts is a lie:
                // on failure the switch goes back to what the worklet is actually doing.
                return .run { send in
                    do {
                        try await zappMessaging.setReadReceiptsEnabled(next)
                        await send(.readReceiptsFinished(next))
                    } catch {
                        LoggerProxy.error("ChatProfile: setReadReceiptsEnabled failed: \(error)")
                        await send(.readReceiptsFinished(previous))
                    }
                }

            case .readReceiptsFinished(let value):
                state.readReceiptsEnabled = value
                state.isReadReceiptsBusy = false
                return .none

            case .presenceToggled:
                guard !state.isPresenceBusy else { return .none }

                let previous = state.presenceVisible
                let next = !previous
                state.presenceVisible = next
                state.isPresenceBusy = true

                return .run { send in
                    do {
                        try await zappMessaging.setPresenceVisible(next)
                        await send(.presenceFinished(next))
                    } catch {
                        LoggerProxy.error("ChatProfile: setPresenceVisible failed: \(error)")
                        await send(.presenceFinished(previous))
                    }
                }

            case .presenceFinished(let value):
                state.presenceVisible = value
                state.isPresenceBusy = false
                return .none

            case .backToHomeTapped:
                return .none
            }
        }
    }

    /// Adopts the worklet's view of the identity without stepping on an edit in progress: the field
    /// only follows the persisted name while the two agree.
    private func seed(_ state: inout State, from messagingState: ZappMessagingState) {
        if let identity = messagingState.identity {
            if state.displayName == state.savedDisplayName {
                state.displayName = identity.displayName
            }

            state.savedDisplayName = identity.displayName
            state.publicKey = identity.publicKey
        }

        if !state.isReadReceiptsBusy {
            state.readReceiptsEnabled = messagingState.readReceiptsEnabled
        }

        if !state.isPresenceBusy {
            state.presenceVisible = messagingState.presenceVisible
        }
    }
}

// MARK: Placeholders

extension ChatProfile.State {
    static var initial: ChatProfile.State {
        .init()
    }
}

extension ChatProfile {
    @MainActor
    static let initial = StoreOf<ChatProfile>(
        initialState: .initial
    ) {
        ChatProfile()
    }
}
