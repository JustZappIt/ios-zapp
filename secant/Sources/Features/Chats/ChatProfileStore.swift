//
//  ChatProfileStore.swift
//  Zapp
//
//  Your own chat identity: the display name peers see and the key they need to reach you.
//
//  Mirrors Android's ChatProfileVM, including its secret-reveal surfaces (seed phrase,
//  P2P wallet key) and Delete identity. The reveals are gated on the app lock and their
//  contents are dropped the moment the app leaves the foreground — see
//  `ChatProfileSecrets.swift`. Wallet addresses live on their own screen, `ChatWalletAddress`.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@Reducer
struct ChatProfile {
    /// Which secret a reveal is being authorised for.
    enum SecretTarget: Equatable {
        case seedPhrase
        case p2pKey
    }

    @ObservableState
    struct State: Equatable {
        var messagingCancelId = UUID()

        /// What the worklet has persisted. Never assumed to satisfy `UsernameRules` — it was
        /// written by whatever version of the app created the identity.
        var displayName = ""

        var publicKey = ""
        var didCopy = false

        /// Non-nil only while the edit-name modal is up.
        var editName: EditName?

        var readReceiptsEnabled = true
        var presenceVisible = true
        var backgroundNotificationsEnabled = false

        /// A privacy call is in flight. The stream still carries the OLD value until the worklet
        /// acknowledges, so an unrelated emission (a peer count tick) would otherwise snap the
        /// optimistic toggle back mid-flight.
        var isReadReceiptsBusy = false
        var isPresenceBusy = false
        var isBackgroundNotificationsBusy = false

        // MARK: Secret reveal — see ChatProfileSecrets.swift

        /// The secret whose authentication is in flight. Cleared as soon as it is shown or aborted.
        var pendingSecret: SecretTarget?

        /// True only between the system biometric sheet going up and its result coming back.
        /// That sheet makes the app resign active, which is one of the `hideSensitiveContent`
        /// triggers — without this flag the app would cancel the very authentication it is
        /// waiting on, and a successful Face ID would reveal nothing at all.
        var isAwaitingBiometric = false

        /// Non-nil while the PIN gate is on screen.
        var pinEntry: PINEntry?

        /// Non-empty only while the seed dialog is up. Cleared on dismiss AND on backgrounding.
        var seedWords: [RedactableString] = []

        /// Non-nil only while the P2P key dialog is up.
        var p2pKey: OfframpWalletKey?

        var didCopyP2PAddress = false
        var didCopyP2PKey = false
        var secretFailed = false

        /// The reveal was refused because the screen was ALREADY being recorded when it was asked
        /// for. Distinct from `secretFailed`, which means the secret could not be read.
        var secretBlockedByCapture = false

        @Presents var alert: AlertState<Action>?

        /// The display-name editor. Keeping the draft in here rather than beside `displayName` is
        /// what stops an incoming identity-stream emission from overwriting an edit in progress.
        struct EditName: Equatable {
            var draft = ""
            var isSaving = false
            var failed = false

            /// Android enables Save for any valid value, changed or not, and lets the SDK absorb
            /// the no-op.
            var canSave: Bool { UsernameRules.isValid(draft) && !isSaving }
        }

        struct PINEntry: Equatable {
            var pin = ""
            var errorMessage: String?
            var lockoutSeconds = 0
            var isVerifying = false
        }

        var hasPublicKey: Bool { !publicKey.isEmpty }

        var showsSeedDialog: Bool { !seedWords.isEmpty }
        var showsP2PKeyDialog: Bool { p2pKey != nil }

        /// Any surface that must never be photographed, recorded, or left up in the app switcher.
        var isShowingSecret: Bool { showsSeedDialog || showsP2PKeyDialog }

        /// Interactive back must not slip out from under a modal — least of all out from under a
        /// save in flight or a revealed secret.
        var isModalPresented: Bool { editName != nil || pinEntry != nil || isShowingSecret }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case messagingStateChanged(ZappMessagingState)
        case copyPublicKeyTapped
        case copyIndicatorExpired
        /// Consumed by Root, which pushes the wallet-address screen.
        case walletAddressTapped
        case readReceiptsToggled
        case readReceiptsFinished(Bool)
        case presenceToggled
        case presenceFinished(Bool)
        case backgroundNotificationsToggled
        case backgroundNotificationsFinished(Bool)

        // MARK: Display name editor
        case editDisplayNameTapped
        case editDisplayNameChanged(String)
        case editDisplayNameSaveTapped
        case editDisplayNameDismissed
        case saveSucceeded(String)
        case saveFailed

        case deleteIdentityTapped
        /// Consumed by Root, which runs the same full reset the Settings path uses.
        case deleteIdentityConfirmed
        case alert(PresentationAction<Action>)

        // MARK: Secret reveal
        case seedPhraseTapped
        case p2pKeyTapped
        case biometricFinished(SecretTarget, Bool)
        case pinKeyTapped(PINKey)
        case pinVerificationFinished(PINVerificationResult)
        case pinLockoutTick
        case pinCancelled
        case secretUnlocked(SecretTarget)
        case seedLoaded([RedactableString])
        case p2pKeyLoaded(OfframpWalletKey)
        case secretLoadFailed
        case secretDismissed
        case copyP2PAddressTapped
        case copyP2PKeyTapped
        case p2pCopyIndicatorExpired
        case hideSensitiveContent
    }

    @Dependency(\.appSecurity) var appSecurity
    @Dependency(\.chatPushNotifications) var chatPushNotifications
    @Dependency(\.continuousClock) var continuousClock
    @Dependency(\.date) var date
    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.screenCapture) var screenCapture
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    enum CancelID {
        case copyIndicator
        case p2pCopyIndicator
        case pinLockout
    }

    var body: some Reducer<State, Action> {
        secretsReduce()
        identityReduce()
        displayNameReduce()
        publicKeyCopyReduce()
        privacyReduce()
        deleteReduce()
            .ifLet(\.$alert, action: \.alert)
    }
}

private extension ChatProfile {
    /// Adopts the worklet's view of the identity.
    func seed(_ state: inout State, from messagingState: ZappMessagingState) {
        if let identity = messagingState.identity {
            state.displayName = identity.displayName
            state.publicKey = identity.publicKey
        }

        if !state.isReadReceiptsBusy {
            state.readReceiptsEnabled = messagingState.readReceiptsEnabled
        }

        if !state.isPresenceBusy {
            state.presenceVisible = messagingState.presenceVisible
        }
    }

    /// Screen lifecycle and the identity stream.
    func identityReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                seed(&state, from: zappMessaging.latestState())
                state.backgroundNotificationsEnabled = chatPushNotifications.isEnabled()

                return .publisher {
                    zappMessaging.stateStream()
                        .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                        .map(Action.messagingStateChanged)
                }
                .cancellable(id: state.messagingCancelId, cancelInFlight: true)

                // Leaving the screen drops the secrets too — see `ChatProfileSecrets.swift`.
                // `didCopy` is cleared alongside its timer: cancelling the one without the other
                // leaves the button reading "Copied" for as long as the state survives.
            case .onDisappear:
                state.didCopy = false

                return .merge(
                    .cancel(id: state.messagingCancelId),
                    .cancel(id: CancelID.copyIndicator),
                    .send(.hideSensitiveContent)
                )

            case .messagingStateChanged(let messagingState):
                seed(&state, from: messagingState)
                return .none

            default:
                return .none
            }
        }
    }

    /// The display-name editor, presented as a modal over the profile.
    func displayNameReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
                // Every opening starts from the persisted name — which predates `UsernameRules`
                // on an old identity, so it is sanitized on the way in.
            case .editDisplayNameTapped:
                state.editName = State.EditName(draft: UsernameRules.sanitize(state.displayName))
                return .none

            case .editDisplayNameChanged(let value):
                state.editName?.draft = UsernameRules.sanitize(value)
                state.editName?.failed = false
                return .none

            case .editDisplayNameSaveTapped:
                guard let editName = state.editName, editName.canSave else { return .none }

                let name = editName.draft
                state.editName?.isSaving = true
                state.editName?.failed = false

                // The SDK only adopts the name once the worklet echoes it back, so a throw means
                // nothing persisted: the modal stays open and the user keeps their edit.
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
                state.displayName = name
                state.editName = nil
                return .none

            case .saveFailed:
                state.editName?.isSaving = false
                state.editName?.failed = true
                return .none

                // A save in flight owns the modal: dismissing under it would strand a write whose
                // result nothing is left to show.
            case .editDisplayNameDismissed:
                guard state.editName?.isSaving == false else { return .none }

                state.editName = nil
                return .none

            default:
                return .none
            }
        }
    }

    /// Copy the key, then flash a tick.
    func publicKeyCopyReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
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

            default:
                return .none
            }
        }
    }

    /// Delete identity, behind Android's `ChatProfileDeleteDialog` confirmation.
    func deleteReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .deleteIdentityTapped:
                state.alert = .deleteIdentity()
                return .none

            case .alert(.presented(let action)):
                state.alert = nil
                return .send(action)

            case .alert(.dismiss):
                state.alert = nil
                return .none

                // `deleteIdentityConfirmed`, `walletAddressTapped` and `backToHomeTapped` are
                // Root's: it owns the reset and the navigation behind them.
            default:
                return .none
            }
        }
    }

    /// The two honour-system privacy switches.
    func privacyReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
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

            case .backgroundNotificationsToggled:
                guard !state.isBackgroundNotificationsBusy else { return .none }

                let requested = !state.backgroundNotificationsEnabled
                state.isBackgroundNotificationsBusy = true

                return .run { send in
                    let enabled = await chatPushNotifications.setEnabled(requested)
                    if enabled {
                        await zappMessaging.syncPushNotifications()
                    }
                    await send(.backgroundNotificationsFinished(enabled))
                }

            case .backgroundNotificationsFinished(let enabled):
                state.backgroundNotificationsEnabled = enabled
                state.isBackgroundNotificationsBusy = false
                return .none

            default:
                return .none
            }
        }
    }
}

// MARK: Alerts

extension AlertState where Action == ChatProfile.Action {
    static func deleteIdentity() -> AlertState {
        AlertState {
            TextState(String(localizable: .chatProfileDeleteTitle))
        } actions: {
            ButtonState(role: .destructive, action: .deleteIdentityConfirmed) {
                TextState(String(localizable: .chatProfileDeleteConfirm))
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(String(localizable: .chatProfileDeleteMessage))
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
