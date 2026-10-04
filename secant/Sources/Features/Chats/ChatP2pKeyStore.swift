//
//  ChatP2pKeyStore.swift
//  Zapp
//
//  Android's `ChatP2pKeyVM`: the P2P wallet key as its own screen, reached from Profile & identity.
//  The smart-account address is safe to share and shows straight away; the owner key stays locked
//  until "Reveal owner key" passes the app lock.
//
//  Same rules as `ChatProfileSecrets.swift`: the key is read only after the gate passes, never
//  logged (it lives in `RedactableString`), and dropped the instant the app stops being frontmost —
//  where Android keeps it on screen until the user leaves.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatP2pKey {
    /// Which value the copy tick is on. A field rather than the copied string, so the private key is
    /// never duplicated into plain state.
    enum CopiedField: Equatable {
        case smartAccount
        case ownerAddress
        case privateKey
    }

    @ObservableState
    struct State: Equatable {
        /// Nil before the lookup finishes and after it fails (a Keystone account has no smart
        /// account) — the card is simply absent, as on Android.
        var smartAccountAddress: String?

        /// Non-nil only while the owner key is revealed.
        var ownerKey: OfframpWalletKey?

        var copiedField: CopiedField?
        var authGate = SecretAuthGate.State()

        /// The gate has passed and the key is being derived.
        var isLoadingKey = false
        var keyFailed = false

        /// The reveal was refused because the screen was ALREADY being recorded.
        var keyBlockedByCapture = false

        var isRevealing: Bool { authGate.isAuthenticating || isLoadingKey }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case smartAccountLoaded(String?)
        case revealTapped
        case authGate(SecretAuthGate.Action)
        case ownerKeyLoaded(OfframpWalletKey)
        case ownerKeyFailed
        case copyTapped(CopiedField)
        case copyIndicatorExpired
        case hideSensitiveContent
        /// Consumed by Root, which returns to Profile & identity.
        case backTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.screenCapture) var screenCapture

    init() { }

    enum CancelID {
        case copyIndicator
        case ownerKey
        case smartAccount
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.authGate, action: \.authGate) {
            SecretAuthGate()
        }

        Reduce { state, action in
            switch action {
                // Android's `GetOfframpBaseAddressUseCase`, via the same client call the wallet
                // address screen uses. Best effort: a failure drops the card, not the screen.
            case .onAppear:
                return .run { send in
                    do {
                        await send(.smartAccountLoaded(try await offramp.accountAddress()))
                    } catch {
                        // Deliberately not interpolating `error`: it can echo back the account.
                        LoggerProxy.warn("ChatP2pKey: smart account address unavailable")
                        await send(.smartAccountLoaded(nil))
                    }
                }
                .cancellable(id: CancelID.smartAccount, cancelInFlight: true)

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.smartAccount),
                    hideKey(&state)
                )

            case .smartAccountLoaded(let address):
                state.smartAccountAddress = (address?.isEmpty ?? true) ? nil : address
                return .none

            case .revealTapped:
                guard state.ownerKey == nil, !state.isRevealing else { return .none }

                state.keyFailed = false
                state.keyBlockedByCapture = false

                // `capturedDidChange` only fires on a transition, so a recording already running
                // when the screen opened never produced one. Ask outright before the gate.
                guard !screenCapture.isCaptured() else {
                    state.keyBlockedByCapture = true
                    return .none
                }
                return .send(.authGate(.start(.allowUnconfigured)))

                // The gate has passed: now, and only now, derive the key.
            case .authGate(.delegate(.authenticated)):
                state.isLoadingKey = true
                return .run { send in
                    do {
                        await send(.ownerKeyLoaded(try await offramp.exportWalletKey()))
                    } catch {
                        LoggerProxy.error("ChatP2pKey: P2P wallet key export failed")
                        await send(.ownerKeyFailed)
                    }
                }
                .cancellable(id: CancelID.ownerKey, cancelInFlight: true)

                // A dismissed prompt is silent, as on Android and the profile's old dialog.
            case .authGate:
                return .none

            case .ownerKeyLoaded(let key):
                state.isLoadingKey = false
                state.ownerKey = key
                return .none

            case .ownerKeyFailed:
                state.isLoadingKey = false
                state.keyFailed = true
                return .none

            case .copyTapped(let field):
                switch field {
                case .smartAccount:
                    guard let address = state.smartAccountAddress else { return .none }
                    pasteboard.setString(RedactableString(address))
                case .ownerAddress:
                    guard let key = state.ownerKey else { return .none }
                    pasteboard.setString(RedactableString(key.address))
                case .privateKey:
                    guard let key = state.ownerKey else { return .none }
                    pasteboard.setString(key.privateKeyHex)
                }
                state.copiedField = field
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyIndicatorExpired)
                }
                .cancellable(id: CancelID.copyIndicator, cancelInFlight: true)

            case .copyIndicatorExpired:
                state.copiedField = nil
                return .none

            case .hideSensitiveContent:
                return hideKey(&state)

            case .backTapped:
                return hideKey(&state)
            }
        }
    }

    /// Drops the owner key and everything that could hint at it. The smart-account address is
    /// safe to share, so it stays.
    private func hideKey(_ state: inout State) -> Effect<Action> {
        state.ownerKey = nil
        state.isLoadingKey = false
        state.keyFailed = false
        state.keyBlockedByCapture = false
        if state.copiedField != .smartAccount {
            state.copiedField = nil
        }

        return .merge(
            .cancel(id: CancelID.ownerKey),
            .send(.authGate(.hide))
        )
    }
}

// MARK: Placeholders

extension ChatP2pKey.State {
    static var initial: ChatP2pKey.State {
        .init()
    }
}

extension ChatP2pKey {
    @MainActor
    static let initial = StoreOf<ChatP2pKey>(
        initialState: .initial
    ) {
        ChatP2pKey()
    }
}
