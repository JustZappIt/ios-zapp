//
//  ChatContactFormStore.swift
//  Zapp
//
//  Add or edit one chat contact. `existing == nil` is the add mode; otherwise the
//  public key is the row's identity and cannot be edited.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatContactForm {
    @ObservableState
    struct State: Equatable {
        /// The chat core caps a contact name at 100; the address book's 32 does not apply here.
        enum Constants {
            static let nameMaxLength = 100
        }

        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty
        @Shared(.inMemory(.zashiWalletAccount)) var zashiWalletAccount: WalletAccount? = nil

        var existing: ChatContact?
        var name = ""
        var publicKey = ""
        var address = ""

        /// Needs `derivationTool`, so the reducer computes it; an empty address is valid.
        var isValidAddress = true

        var isEditing: Bool { existing != nil }
        var isBlocked: Bool { existing?.isBlocked ?? false }

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

        var canSave: Bool {
            isValidName && isValidKey && !isDuplicateKey && isValidAddress
        }

        init(existing: ChatContact? = nil) {
            self.existing = existing
            self.name = existing?.name ?? ""
            self.publicKey = existing?.publicKey ?? ""
            self.address = existing?.address ?? ""
        }
    }

    enum Action: Equatable {
        case onAppear
        case closeTapped
        case nameChanged(String)
        case publicKeyChanged(String)
        case addressChanged(String)
        case saveTapped
        case blockTapped
        case deleteTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case contactsChanged(ChatContacts)
        }
    }

    @Dependency(\.chatContacts) var chatContacts
    @Dependency(\.derivationTool) var derivationTool
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isValidAddress = isValidAddress(state.trimmedAddress)
                return .none

            case .nameChanged(let value):
                state.name = String(value.prefix(State.Constants.nameMaxLength))
                return .none

            case .publicKeyChanged(let value):
                guard !state.isEditing else { return .none }
                state.publicKey = PublicKeyRules.sanitize(value)
                return .none

            case .addressChanged(let value):
                state.address = value
                state.isValidAddress = isValidAddress(state.trimmedAddress)
                return .none

            case .saveTapped:
                guard state.canSave, let account = state.zashiWalletAccount else { return .none }

                let contact = ChatContact(
                    publicKey: state.publicKey,
                    name: state.trimmedName,
                    address: state.trimmedAddress,
                    walletAddresses: state.existing?.walletAddresses ?? [:],
                    isBlocked: state.isBlocked,
                    isSaved: true
                )

                do {
                    return .send(.delegate(.contactsChanged(try chatContacts.save(account.account, contact))))
                } catch {
                    LoggerProxy.error("Chat contact save failed: \(error)")
                    return .none
                }

            case .blockTapped:
                guard let existing = state.existing, let account = state.zashiWalletAccount else { return .none }

                do {
                    let contacts = try chatContacts.setBlocked(
                        account.account,
                        existing.publicKey,
                        existing.name,
                        !existing.isBlocked
                    )
                    return .send(.delegate(.contactsChanged(contacts)))
                } catch {
                    LoggerProxy.error("Chat contact block toggle failed: \(error)")
                    return .none
                }

            case .deleteTapped:
                guard let existing = state.existing, let account = state.zashiWalletAccount else { return .none }

                do {
                    let contacts = try chatContacts.delete(account.account, existing.publicKey)
                    return .send(.delegate(.contactsChanged(contacts)))
                } catch {
                    LoggerProxy.error("Chat contact delete failed: \(error)")
                    return .none
                }

            case .closeTapped:
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func isValidAddress(_ address: String) -> Bool {
        address.isEmpty || derivationTool.isZcashAddress(address, zcashSDKEnvironment.network().networkType)
    }
}
