//
//  ViewingKeyExportStore.swift
//  Zapp
//
//  Android's `ViewingKeyExportVM`: export a unified viewing key (UFVK or UIVK) for one account, so
//  a dashboard or accounting tool can watch it without being able to spend.
//
//  The flow is Android's: pick the account (only offered with more than one), pick the access
//  level, acknowledge that the export is irrevocable, then authenticate. The key is read from the
//  SDK only after the gate passes, lives in a `RedactableString` while it is shown, and is dropped
//  the moment the app stops being frontmost, the screen goes away, or the user picks another
//  account or level.
//

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

@Reducer
struct ViewingKeyExport {
    /// Android's `ViewingKeyType`.
    enum KeyType: Equatable, CaseIterable, Sendable {
        case ufvk
        case uivk
    }

    /// Android's `ViewingKeyExportAccount`. Carries which keys exist, never the keys themselves.
    struct AccountItem: Equatable, Identifiable {
        let id: AccountUUID
        let title: String
        let accountIndex: UInt32?
        let isSelected: Bool
        let availableKeyTypes: Set<KeyType>

        /// Android prefers the full key and falls back to the incoming one.
        var preferredKeyType: KeyType {
            availableKeyTypes.contains(.ufvk) || !availableKeyTypes.contains(.uivk) ? .ufvk : .uivk
        }

        init(_ account: WalletAccount, selectedId: AccountUUID?) {
            id = account.id
            title = account.vendor.name()
            accountIndex = account.zip32AccountIndex?.index
            isSelected = account.id == selectedId
            var types = Set<KeyType>()
            if account.account.ufvk != nil { types.insert(.ufvk) }
            if account.account.uivk != nil { types.insert(.uivk) }
            availableKeyTypes = types
        }
    }

    /// Android's `ViewingKeyExportData`.
    struct RevealedKey: Equatable, Sendable {
        let keyType: KeyType
        let encodedKey: RedactableString
    }

    /// Android's `ViewingKeyExportError`, minus `SHARE_FAILED` (the iOS share sheet has no failure
    /// to report) and plus the iOS refusal to reveal into a running screen recording.
    enum ExportError: Equatable {
        case loadFailed
        case authenticationFailed
        case keyUnavailable
        case screenRecording
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount?

        var accounts: [AccountItem] = []
        var selectedAccountId: AccountUUID?
        var selectedKeyType: KeyType = .ufvk
        var isAcknowledged = false
        var isLoading = true

        /// The gate has passed and the key is being read.
        var isReadingKey = false
        var isCopied = false
        var revealedKey: RevealedKey?
        var error: ExportError?

        /// Non-nil while the share sheet is up. Cleared with the key.
        var sharedKey: RedactableString?

        var authGate = SecretAuthGate.State()

        var selectedAccount: AccountItem? {
            accounts.first { $0.id == selectedAccountId }
        }

        var isSelectedKeyAvailable: Bool {
            selectedAccount?.availableKeyTypes.contains(selectedKeyType) ?? false
        }

        var isAuthenticating: Bool { authGate.isAuthenticating || isReadingKey }

        var canReveal: Bool {
            isAcknowledged && isSelectedKeyAvailable && !isLoading && !isAuthenticating && revealedKey == nil
        }

        /// Account, level and acknowledgement are frozen while a reveal is in flight or a key is up.
        var isSelectionEnabled: Bool { revealedKey == nil && !isAuthenticating }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case accountsLoaded([AccountItem])
        case accountsLoadFailed
        case accountSelected(AccountUUID)
        case keyTypeSelected(KeyType)
        case acknowledgementToggled
        case revealTapped
        case authGate(SecretAuthGate.Action)
        case keyLoaded(RevealedKey?)
        case copyTapped
        case copyIndicatorExpired
        case shareTapped
        case shareFinished
        case hideTapped
        case hideSensitiveContent
        /// Consumed by Root, which returns to the You tab.
        case backTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.screenCapture) var screenCapture
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer

    init() { }

    enum CancelID {
        case accounts
        case copyIndicator
        case reveal
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.authGate, action: \.authGate) {
            SecretAuthGate()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                let selectedId = state.selectedWalletAccount?.id
                return .run { send in
                    do {
                        let accounts = try await sdkSynchronizer.walletAccounts()
                        await send(.accountsLoaded(accounts.map { AccountItem($0, selectedId: selectedId) }))
                    } catch {
                        LoggerProxy.error("ViewingKeyExport: wallet accounts could not be listed")
                        await send(.accountsLoadFailed)
                    }
                }
                .cancellable(id: CancelID.accounts, cancelInFlight: true)

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.accounts),
                    hideKey(&state)
                )

            case .accountsLoaded(let accounts):
                let selected = accounts.first(where: \.isSelected) ?? accounts.first
                state.accounts = accounts
                state.selectedAccountId = selected?.id
                state.selectedKeyType = selected?.preferredKeyType ?? .ufvk
                state.isLoading = false
                return .none

            case .accountsLoadFailed:
                state.isLoading = false
                state.error = .loadFailed
                return .none

            case .accountSelected(let id):
                guard state.isSelectionEnabled, let account = state.accounts.first(where: { $0.id == id }) else {
                    return .none
                }

                state.selectedAccountId = id
                if !account.availableKeyTypes.contains(state.selectedKeyType) {
                    state.selectedKeyType = account.preferredKeyType
                }
                state.isAcknowledged = false
                state.isCopied = false
                state.error = nil
                return .none

            case .keyTypeSelected(let keyType):
                guard state.isSelectionEnabled, state.selectedAccount?.availableKeyTypes.contains(keyType) == true else {
                    return .none
                }

                state.selectedKeyType = keyType
                state.isAcknowledged = false
                state.isCopied = false
                state.error = nil
                return .none

            case .acknowledgementToggled:
                guard state.isSelectionEnabled, state.isSelectedKeyAvailable else { return .none }

                state.isAcknowledged.toggle()
                state.error = nil
                return .none

            case .revealTapped:
                guard state.canReveal else { return .none }

                state.error = nil

                // `capturedDidChange` only fires on a transition, so a recording already running
                // when the screen opened never produced one. Ask outright before the gate.
                guard !screenCapture.isCaptured() else {
                    state.error = .screenRecording
                    return .none
                }
                return .send(.authGate(.start(.requireAuthentication)))

                // The gate has passed: now, and only now, read the key. Re-listed from the SDK
                // rather than taken from shared state, as Android re-reads its data source.
            case .authGate(.delegate(.authenticated)):
                guard let accountId = state.selectedAccountId else { return .none }

                state.isReadingKey = true
                let keyType = state.selectedKeyType
                return .run { send in
                    let account = try? await sdkSynchronizer.walletAccounts().first { $0.id == accountId }
                    let encoded: String? = switch keyType {
                    case .ufvk: account?.account.ufvk?.stringEncoded
                    case .uivk: account?.account.uivk?.stringEncoded
                    }
                    if encoded == nil {
                        LoggerProxy.error("ViewingKeyExport: the selected viewing key is unavailable")
                    }
                    await send(.keyLoaded(encoded.map { RevealedKey(keyType: keyType, encodedKey: RedactableString($0)) }))
                }
                .cancellable(id: CancelID.reveal, cancelInFlight: true)

            case .authGate(.delegate(.failed)):
                state.error = .authenticationFailed
                return .none

            case .authGate:
                return .none

            case .keyLoaded(let key):
                state.isReadingKey = false
                state.revealedKey = key
                state.error = key == nil ? .keyUnavailable : nil
                return .none

            case .copyTapped:
                guard let key = state.revealedKey else { return .none }

                pasteboard.setString(key.encodedKey)
                state.isCopied = true
                state.error = nil
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyIndicatorExpired)
                }
                .cancellable(id: CancelID.copyIndicator, cancelInFlight: true)

            case .copyIndicatorExpired:
                state.isCopied = false
                return .none

            case .shareTapped:
                guard let key = state.revealedKey else { return .none }

                state.error = nil
                state.sharedKey = key.encodedKey
                return .none

            case .shareFinished:
                state.sharedKey = nil
                return .none

            case .hideTapped, .hideSensitiveContent, .backTapped:
                return hideKey(&state)
            }
        }
    }

    /// Android's `hideKey()`: drops the key and everything that could hint at it, and abandons a
    /// reveal still in flight.
    private func hideKey(_ state: inout State) -> Effect<Action> {
        state.revealedKey = nil
        state.sharedKey = nil
        state.isReadingKey = false
        state.isCopied = false
        state.error = nil

        return .merge(
            .cancel(id: CancelID.reveal),
            .cancel(id: CancelID.copyIndicator),
            .send(.authGate(.hide))
        )
    }
}

// MARK: Placeholders

extension ViewingKeyExport.State {
    static var initial: ViewingKeyExport.State {
        .init()
    }
}

extension ViewingKeyExport {
    @MainActor
    static let initial = StoreOf<ViewingKeyExport>(
        initialState: .initial
    ) {
        ViewingKeyExport()
    }
}
