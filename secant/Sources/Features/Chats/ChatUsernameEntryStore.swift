//
//  ChatUsernameEntryStore.swift
//  Zapp
//
//  The username step inside wallet create / restore.
//
//  Ordering is not arbitrary: the wallet must exist first, because the chat
//  identity is derived from its 24-word seed. Android's onboarding says the same
//  thing in its own KDoc. So this is pushed AFTER importWallet succeeds.
//
//  The name is only queued here. Derivation happens whenever the worklet finishes
//  booting — `ZappMessagingImpl.start()` re-attempts the derive the moment it
//  reaches `.needsIdentity`, so a name captured before the worklet is up is not
//  lost. That is why this screen does not wait on, or show, the derive.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatUsernameEntry {
    @ObservableState
    struct State: Equatable {
        var displayName = ""

        var isValid: Bool { UsernameRules.isValid(displayName) }

        init() { }
    }

    enum Action: Equatable {
        case displayNameChanged(String)
        case continueTapped
    }

    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .displayNameChanged(let value):
                state.displayName = UsernameRules.sanitize(value)
                return .none

            case .continueTapped:
                guard state.isValid else { return .none }
                zappMessaging.setDisplayName(state.displayName)
                // The coord flow advances on this action; it is not handled here.
                return .none
            }
        }
    }
}

extension ChatUsernameEntry.State {
    static var initial: ChatUsernameEntry.State { .init() }
}
