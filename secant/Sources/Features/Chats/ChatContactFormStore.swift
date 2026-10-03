//
//  ChatContactFormStore.swift
//  Zapp
//
//  Add or edit one chat contact. `existing == nil` is the add mode; otherwise the
//  public key is the row's identity and cannot be edited.
//
//  Mirrors Android's AddChatContactVM / EditChatContactVM: name, messaging key, primary
//  ZEC address, and the collapsible "additional addresses" block (transparent / EVM /
//  Solana), each field with its own QR-scan affordance that routes the result back to
//  the field that asked for it.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatContactForm {
    /// Which field a presented scanner is filling. Android keeps the same idea in
    /// `scanTargetField`, where `null` means "the primary wallet address".
    enum ScanTarget: Equatable {
        case publicKey
        case address
        case transparent
        case evm
        case solana
    }

    /// The fields Android's edit sheet offers a copy action on.
    enum CopyField: Equatable {
        case name
        case publicKey
        case address
    }

    @ObservableState
    struct State: Equatable {
        /// The chat core caps a contact name at 100; the address book's 32 does not apply here.
        enum Constants {
            static let nameMaxLength = 100
        }

        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty
        @Shared(.inMemory(.zashiWalletAccount)) var zashiWalletAccount: WalletAccount? = nil

        @Presents var scan: Scan.State?
        @Presents var alert: AlertState<Action>?

        var existing: ChatContact?

        /// Set when the form is opened for a peer that is not a saved contact yet — the chat
        /// room's "add this person" entry. It supplies the key (which stays locked, since it
        /// identifies the conversation) and gives Block something to act on before a row exists.
        var prefill: ChatContact?

        var name = ""
        var publicKey = ""
        var address = ""

        var transparentAddress = ""
        var evmAddress = ""
        var solanaAddress = ""

        /// Collapsed by default, matching Android, but opened when the contact already carries
        /// one of the extra addresses so an edit never hides data the user has saved.
        var showsAdditionalAddresses = false

        var scanTarget: ScanTarget?

        /// Needs `derivationTool`, so the reducer computes it; an empty address is valid.
        var isValidAddress = true

        /// Android's inline "Delete contact? This cannot be undone." panel, in place of the buttons.
        var isConfirmingDelete = false

        /// Android's single inline error line: a save or delete the store refused.
        var errorMessage: String?

        var copiedField: CopyField?

        var isEditing: Bool { existing != nil }

        /// The key is the row's identity everywhere it is already known — a saved contact, or a
        /// peer we opened the form for from their conversation.
        var isKeyLocked: Bool { existing != nil || prefill != nil }

        /// Blocking works before a contact exists: the client upserts a block-only row.
        var blockTarget: ChatContact? { existing ?? prefill }
        var isBlocked: Bool { blockTarget?.isBlocked ?? false }
        var canBlock: Bool { blockTarget != nil }

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

        var isValidName: Bool { !trimmedName.isEmpty }
        var isValidKey: Bool { PublicKeyRules.isValid(publicKey) }

        var showsInvalidKeyHint: Bool { !publicKey.isEmpty && !isValidKey }

        /// A block-only row is not a contact: saving over it upserts and keeps the block, which is
        /// how someone re-adds a stranger they once blocked. Only a saved row is a duplicate.
        var isDuplicateKey: Bool {
            guard isValidKey, publicKey != existing?.publicKey else { return false }

            return chatContacts.saved.contains { PublicKeyRules.sanitize($0.publicKey) == publicKey }
        }

        /// Android's `EditChatContactVM.isSaveEnabled`: an edit needs something to save. A peer that
        /// is not a contact yet can be saved as it stands — saving is what makes it one.
        var hasChanges: Bool {
            guard let existing else { return true }

            return trimmedName != existing.name
                || trimmedAddress != existing.address
                || walletAddresses != existing.walletAddresses
        }

        var canSave: Bool {
            isValidName && isValidKey && !isDuplicateKey && isValidAddress && hasChanges
        }

        /// What `saveTapped` persists. Only the three typed keys are rewritten; anything else
        /// already on the record (a type this build does not know about, written by a newer
        /// Android) is carried through untouched.
        var walletAddresses: [String: String] {
            var addresses = existing?.walletAddresses ?? prefill?.walletAddresses ?? [:]

            addresses[ChatContact.AddrType.transparent] = Self.trimmedOrNil(transparentAddress)
            addresses[ChatContact.AddrType.evm] = Self.trimmedOrNil(evmAddress)
            addresses[ChatContact.AddrType.solana] = Self.trimmedOrNil(solanaAddress)

            return addresses
        }

        private static func trimmedOrNil(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            return trimmed.isEmpty ? nil : trimmed
        }

        init(existing: ChatContact? = nil, prefill: ChatContact? = nil) {
            self.existing = existing
            self.prefill = prefill

            let seed = existing ?? prefill
            self.name = seed?.name ?? ""
            self.publicKey = seed?.publicKey ?? ""
            self.address = seed?.address ?? ""

            let addresses = seed?.walletAddresses ?? [:]
            self.transparentAddress = addresses[ChatContact.AddrType.transparent] ?? ""
            self.evmAddress = addresses[ChatContact.AddrType.evm] ?? ""
            self.solanaAddress = addresses[ChatContact.AddrType.solana] ?? ""
            self.showsAdditionalAddresses = !transparentAddress.isEmpty
                || !evmAddress.isEmpty
                || !solanaAddress.isEmpty
        }
    }

    enum Action: Equatable {
        case onAppear
        case closeTapped
        case nameChanged(String)
        case publicKeyChanged(String)
        case addressChanged(String)
        case transparentAddressChanged(String)
        case evmAddressChanged(String)
        case solanaAddressChanged(String)
        case additionalAddressesToggled
        case scanTapped(ScanTarget)
        case scan(PresentationAction<Scan.Action>)
        case alert(PresentationAction<Action>)
        case copyTapped(CopyField)
        case copyIndicatorExpired
        case saveTapped
        case blockTapped
        case blockConfirmed
        case deleteTapped
        case deleteCancelled
        case deleteConfirmed
        case delegate(Delegate)

        enum Delegate: Equatable {
            case contactsChanged(ChatContacts)
        }
    }

    @Dependency(\.chatContacts) var chatContacts
    @Dependency(\.derivationTool) var derivationTool
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    private enum CancelID { case copyIndicator }

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isValidAddress = isValidAddress(state.trimmedAddress)
                return .none

            case .nameChanged(let value):
                state.name = String(value.prefix(State.Constants.nameMaxLength))
                state.errorMessage = nil
                return .none

            case .publicKeyChanged(let value):
                guard !state.isKeyLocked else { return .none }
                state.publicKey = PublicKeyRules.sanitize(value)
                return .none

            case .addressChanged(let value):
                state.address = value
                state.isValidAddress = isValidAddress(state.trimmedAddress)
                state.errorMessage = nil
                return .none

            case .copyTapped(let field):
                let value: String
                switch field {
                case .name: value = state.trimmedName
                case .publicKey: value = state.publicKey
                case .address: value = state.trimmedAddress
                }
                guard !value.isEmpty else { return .none }

                pasteboard.setString(RedactableString(value))
                state.copiedField = field
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyIndicatorExpired)
                }
                .cancellable(id: CancelID.copyIndicator, cancelInFlight: true)

            case .copyIndicatorExpired:
                state.copiedField = nil
                return .none

            case .transparentAddressChanged(let value):
                state.transparentAddress = value
                return .none

            case .evmAddressChanged(let value):
                state.evmAddress = value
                return .none

            case .solanaAddressChanged(let value):
                state.solanaAddress = value
                return .none

            case .additionalAddressesToggled:
                state.showsAdditionalAddresses.toggle()
                return .none

            case .scanTapped(let target):
                guard target != .publicKey || !state.isKeyLocked else { return .none }

                state.scanTarget = target
                var scanState = Scan.State.initial
                scanState.checkers = checkers(for: target)
                if target == .publicKey {
                    scanState.instructions = String(localizable: .newChatScanInstructions)
                }
                state.scan = scanState
                return .none

            case .scan(.presented(.foundString(let value))):
                return apply(scanned: value, to: &state)

            case .scan(.presented(.foundAddress(let value))):
                return apply(scanned: value.data, to: &state)

            case .scan(.presented(.cancelTapped)), .scan(.dismiss):
                state.scan = nil
                state.scanTarget = nil
                return .none

            case .scan:
                return .none

            case .saveTapped:
                guard state.canSave, let account = state.zashiWalletAccount else { return .none }

                let contact = ChatContact(
                    publicKey: state.publicKey,
                    name: state.trimmedName,
                    address: state.trimmedAddress,
                    walletAddresses: state.walletAddresses,
                    isBlocked: state.isBlocked,
                    isSaved: true
                )

                state.errorMessage = nil
                do {
                    return .send(.delegate(.contactsChanged(try chatContacts.save(account.account, contact))))
                } catch {
                    LoggerProxy.error("Chat contact save failed: \(error)")
                    state.errorMessage = String(localizable: .chatContactsSaveFailed)
                    return .none
                }

                // Android confirms in `BlockUserDialog` before writing; the block is silent to the
                // other side, so the only chance to change your mind is before it lands.
            case .blockTapped:
                guard let target = state.blockTarget else { return .none }

                state.alert = .blockContact(name: target.name, isUnblock: target.isBlocked)
                return .none

            case .blockConfirmed:
                guard let target = state.blockTarget, let account = state.zashiWalletAccount else { return .none }

                do {
                    let contacts = try chatContacts.setBlocked(
                        account.account,
                        target.publicKey,
                        target.name,
                        !target.isBlocked
                    )
                    return .send(.delegate(.contactsChanged(contacts)))
                } catch {
                    // Android's dialog dismisses only on success, so a failed write leaves it up
                    // to retry rather than letting the user walk away believing it took effect.
                    LoggerProxy.error("Chat contact block toggle failed: \(error)")
                    state.alert = .blockContact(name: target.name, isUnblock: target.isBlocked)
                    return .none
                }

            case .alert(.presented(let action)):
                state.alert = nil
                return .send(action)

            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .alert:
                return .none

                // Android asks inline first: a contact's name and address are not recoverable.
            case .deleteTapped:
                guard state.isEditing else { return .none }
                state.isConfirmingDelete = true
                return .none

            case .deleteCancelled:
                state.isConfirmingDelete = false
                return .none

            case .deleteConfirmed:
                guard let existing = state.existing, let account = state.zashiWalletAccount else { return .none }

                do {
                    let contacts = try chatContacts.delete(account.account, existing.publicKey)
                    return .send(.delegate(.contactsChanged(contacts)))
                } catch {
                    LoggerProxy.error("Chat contact delete failed: \(error)")
                    state.isConfirmingDelete = false
                    state.errorMessage = String(localizable: .chatContactsDeleteFailed)
                    return .none
                }

            case .closeTapped:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$scan, action: \.scan) {
            Scan()
        }
        .ifLet(\.$alert, action: \.alert)
    }

    /// The primary ZEC field takes a Zcash URI or a bare address; the chain-specific fields take
    /// whatever the QR carries, since only their own chain can validate them.
    private func checkers(for target: ScanTarget) -> [ScanCheckerWrapper] {
        switch target {
        case .publicKey: return [.chatPublicKeyScanChecker]
        case .address: return [.zcashAddressScanChecker, .swapStringScanChecker]
        case .transparent, .evm, .solana: return [.swapStringScanChecker]
        }
    }

    private func apply(scanned value: String, to state: inout State) -> Effect<Action> {
        guard let target = state.scanTarget else { return .none }

        state.scan = nil
        state.scanTarget = nil

        switch target {
        case .publicKey:
            guard !state.isKeyLocked else { return .none }
            state.publicKey = PublicKeyRules.sanitize(value)

        case .address:
            state.address = value
            state.isValidAddress = isValidAddress(state.trimmedAddress)

            // A scan into one of the extra fields has to reveal the section it landed in,
            // or the value is written somewhere the user cannot see.
        case .transparent:
            state.transparentAddress = value
            state.showsAdditionalAddresses = true

        case .evm:
            state.evmAddress = value
            state.showsAdditionalAddresses = true

        case .solana:
            state.solanaAddress = value
            state.showsAdditionalAddresses = true
        }

        return .none
    }

    private func isValidAddress(_ address: String) -> Bool {
        address.isEmpty || derivationTool.isZcashAddress(address, zcashSDKEnvironment.network().networkType)
    }
}

// MARK: Alerts

extension AlertState where Action == ChatContactForm.Action {
    static func blockContact(name: String, isUnblock: Bool) -> AlertState {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localizable: .chatModerationFallbackUser)
            : name

        return AlertState {
            TextState(
                isUnblock
                    ? String(localizable: .chatBlockUnblockTitle)
                    : String(localizable: .chatBlockTitle)
            )
        } actions: {
            ButtonState(role: .destructive, action: .blockConfirmed) {
                TextState(
                    isUnblock
                        ? String(localizable: .chatBlockUnblockConfirm)
                        : String(localizable: .chatBlockConfirm)
                )
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(
                isUnblock
                    ? String(localizable: .chatBlockUnblockMessage(target))
                    : String(localizable: .chatBlockMessage(target))
            )
        }
    }
}
