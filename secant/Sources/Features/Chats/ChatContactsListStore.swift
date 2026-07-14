//
//  ChatContactsListStore.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatContactsList {
    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty
        @Shared(.inMemory(.zashiWalletAccount)) var zashiWalletAccount: WalletAccount? = nil

        @Presents var form: ChatContactForm.State?

        /// Block-only rows are not contacts, so the list never shows them.
        var contacts: [ChatContact] { chatContacts.saved }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case backToHomeTapped
        case addTapped
        case contactTapped(ChatContact)
        case form(PresentationAction<ChatContactForm.Action>)

        /// Root owns the shared projection; a mutation is handed up rather than written here.
        case contactsChanged(ChatContacts)
    }

    @Dependency(\.chatContacts) var chatContacts

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard let account = state.zashiWalletAccount else { return .none }

                do {
                    return .send(.contactsChanged(try chatContacts.all(account.account)))
                } catch {
                    LoggerProxy.error("Chat contacts failed to load: \(error)")
                    return .none
                }

            case .addTapped:
                state.form = ChatContactForm.State()
                return .none

            case .contactTapped(let contact):
                state.form = ChatContactForm.State(existing: contact)
                return .none

            case .form(.presented(.delegate(.contactsChanged(let contacts)))):
                state.form = nil
                return .send(.contactsChanged(contacts))

            case .form(.presented(.closeTapped)):
                state.form = nil
                return .none

            case .form:
                return .none

            case .contactsChanged:
                return .none

            case .backToHomeTapped:
                return .none
            }
        }
        .ifLet(\.$form, action: \.form) {
            ChatContactForm()
        }
    }
}

extension ChatContactsList.State {
    static var initial: ChatContactsList.State { .init() }
}
