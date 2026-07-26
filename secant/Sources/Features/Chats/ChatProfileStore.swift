//
//  ChatProfileStore.swift
//  Zapp
//
//  Your own chat identity: the display name peers see, the key they need to reach you,
//  the wallet addresses they can pay, and the two privacy switches.
//
//  Mirrors Android's ChatProfileVM, including its secret-reveal surfaces (seed phrase,
//  P2P wallet key) and Delete identity. The reveals are gated on the app lock and their
//  contents are dropped the moment the app leaves the foreground — see
//  `ChatProfileSecrets.swift`.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@Reducer
struct ChatProfile {
    /// Android's `ChatProfileTab`.
    enum Tab: Int, Equatable, CaseIterable {
        case messagingID
        case walletAddress
    }

    /// Android's `ChatProfileWalletSubTab`.
    enum WalletSubTab: Int, Equatable, CaseIterable {
        case shielded
        case transparent
    }

    /// Which secret a reveal is being authorised for.
    enum SecretTarget: Equatable {
        case seedPhrase
        case p2pKey
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.zashiWalletAccount)) var zashiWalletAccount: WalletAccount?

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

        var activeTab = Tab.messagingID
        var walletSubTab = WalletSubTab.shielded
        var didCopyAddress = false

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

        @Presents var alert: AlertState<Action>?

        struct PINEntry: Equatable {
            var pin = ""
            var errorMessage: String?
            var lockoutSeconds = 0
            var isVerifying = false
        }

        var isNameValid: Bool { UsernameRules.isValid(displayName) }
        var isNameChanged: Bool { displayName != savedDisplayName }
        var canSave: Bool { isNameValid && isNameChanged && !isSaving }
        var hasPublicKey: Bool { !publicKey.isEmpty }

        var shieldedAddress: String? { zashiWalletAccount?.unifiedAddress }
        var transparentAddress: String? { zashiWalletAccount?.transparentAddress }

        var selectedWalletAddress: String? {
            switch walletSubTab {
            case .shielded: return shieldedAddress
            case .transparent: return transparentAddress
            }
        }

        /// Android only offers the sub-tabs once there is a shielded address to switch away from.
        var showsWalletSubTabs: Bool { activeTab == .walletAddress && shieldedAddress != nil }

        /// Android shows the P2P key row on the wallet tab only — it is a wallet key, not a
        /// messaging one. The seed phrase backs up both identities, so it is always offered.
        var showsP2PKeyRow: Bool { activeTab == .walletAddress }

        var showsSeedDialog: Bool { !seedWords.isEmpty }
        var showsP2PKeyDialog: Bool { p2pKey != nil }

        /// Any surface that must never be photographed, recorded, or left up in the app switcher.
        var isShowingSecret: Bool { showsSeedDialog || showsP2PKeyDialog }

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

        case tabSelected(Tab)
        case walletSubTabSelected(WalletSubTab)
        case copyAddressTapped
        case copyAddressIndicatorExpired

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
    @Dependency(\.continuousClock) var continuousClock
    @Dependency(\.date) var date
    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    enum CancelID {
        case copyIndicator
        case addressCopyIndicator
        case p2pCopyIndicator
        case pinLockout
    }

    var body: some Reducer<State, Action> {
        secretsReduce()
        identityReduce()
        displayNameReduce()
        surfaceReduce()
        privacyReduce()
        deleteReduce()
            .ifLet(\.$alert, action: \.alert)
    }
}

private extension ChatProfile {
    /// Adopts the worklet's view of the identity without stepping on an edit in progress: the field
    /// only follows the persisted name while the two agree.
    func seed(_ state: inout State, from messagingState: ZappMessagingState) {
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

    /// Screen lifecycle and the identity stream.
    func identityReduce() -> Reduce<State, Action> {
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

                // Leaving the screen drops the secrets too — see `ChatProfileSecrets.swift`.
            case .onDisappear:
                return .merge(
                    .cancel(id: state.messagingCancelId),
                    .cancel(id: CancelID.copyIndicator),
                    .cancel(id: CancelID.addressCopyIndicator),
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

    /// The display-name editor.
    func displayNameReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
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

            default:
                return .none
            }
        }
    }

    /// Tabs and the two "copy, then flash a tick" affordances.
    func surfaceReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                state.activeTab = tab
                return .none

            case .walletSubTabSelected(let tab):
                state.walletSubTab = tab
                state.didCopyAddress = false
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

            case .copyAddressTapped:
                guard let address = state.selectedWalletAddress, !address.isEmpty else { return .none }

                pasteboard.setString(RedactableString(address))
                state.didCopyAddress = true

                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyAddressIndicatorExpired)
                }
                .cancellable(id: CancelID.addressCopyIndicator, cancelInFlight: true)

            case .copyAddressIndicatorExpired:
                state.didCopyAddress = false
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

                // Root runs the reset; nothing to do locally.
            case .alert, .deleteIdentityConfirmed, .backToHomeTapped:
                return .none

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
