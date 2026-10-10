//
//  ChatContactsListStore.swift
//  Zapp
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct ChatContactsList {
    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty
        @Shared(.inMemory(.zashiWalletAccount)) var zashiWalletAccount: WalletAccount? = nil

        @Presents var form: ChatContactForm.State?

        /// A Start-chat tap is in flight; a second tap would race the first to open the room.
        var isStartingChat = false

        /// Block-only rows are not contacts, so the list never shows them.
        var contacts: [ChatContact] { chatContacts.saved }

        /// Android's A–Z grouping: by the name's first character, upper-cased, `?` for none.
        var sections: [Section] {
            var sections: [Section] = []
            for contact in contacts {
                let letter = contact.name.first.map { String($0).uppercased() } ?? "?"
                if sections.last?.letter == letter {
                    sections[sections.count - 1].contacts.append(contact)
                } else {
                    sections.append(Section(letter: letter, contacts: [contact]))
                }
            }
            return sections
        }

        struct Section: Equatable, Identifiable {
            let letter: String
            var contacts: [ChatContact]

            var id: String { letter }
        }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case backToHomeTapped
        case addTapped
        case contactTapped(ChatContact)
        case startChatTapped(ChatContact)
        case startChatFailed
        /// Consumed by Root, which lands the user in the room, as Android's `onStartChat` does.
        case conversationOpened(ZMConversation)
        case form(PresentationAction<ChatContactForm.Action>)

        /// Root owns the shared projection; a mutation is handed up rather than written here.
        case contactsChanged(ChatContacts)
    }

    @Dependency(\.chatContacts) var chatContacts
    @Dependency(\.zappMessaging) var zappMessaging

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

                // Re-opens the existing DM when there is one; the core keys a direct conversation
                // on its participant. A blocked contact has no Start-chat button to send this.
            case .startChatTapped(let contact):
                guard !state.isStartingChat, !contact.isBlocked else { return .none }

                state.isStartingChat = true
                return .run { send in
                    await send(.conversationOpened(try await zappMessaging.createDirectConversation(contact.publicKey, nil)))
                } catch: { error, send in
                    LoggerProxy.event("ChatContactsList: createDirectConversation failed: \(error)")
                    await send(.startChatFailed)
                }

            case .startChatFailed:
                state.isStartingChat = false
                return .none

            case .conversationOpened:
                state.isStartingChat = false
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
