//
//  RootChatContacts.swift
//  Zapp
//
//  Root hydrates chat contacts into shared state, the same way it hydrates the
//  address book. Everything downstream — name resolution, blocked filtering, the
//  contact picker — reads that projection rather than hitting the encrypted file.
//

import ComposableArchitecture
import Foundation

extension Root {
    func chatContactsReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case .loadChatContacts:
                guard let account = state.zashiWalletAccount else { return .none }

                do {
                    return .send(.chatContactsLoaded(try chatContacts.all(account.account)))
                } catch {
                    // A decrypt/version failure must not be swallowed into an empty
                    // set — an empty set would then be written back over the file.
                    LoggerProxy.event("Chat contacts failed to load: \(error)")
                    return .none
                }

            case .chatContactsLoaded(let contacts):
                state.$chatContacts.withLock { $0 = contacts }
                zappMessaging.setBlockedKeys(contacts.blockedKeys)
                return .none

            default: return .none
            }
        }
    }
}
