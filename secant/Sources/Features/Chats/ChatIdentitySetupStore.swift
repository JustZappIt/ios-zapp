//
//  ChatIdentitySetupStore.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@Reducer
struct ChatIdentitySetup {
    @ObservableState
    struct State: Equatable {
        var messagingCancelId = UUID()

        var displayName = ""
        var messagingState = ZappMessagingState()

        var isValid: Bool { UsernameRules.isValid(displayName) }

        /// A failed derive and a failed worklet boot land the form in the same shape: message, raw
        /// code, retry. They differ only in where the subsystem parks the code.
        var errorCode: String? {
            if case .failed(let code) = messagingState.phase {
                return code
            }

            return messagingState.identityErrorCode
        }

        init() { }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<ChatIdentitySetup.State>)
        case continueTapped
        case displayNameChanged(String)
        case messagingStateChanged(ZappMessagingState)
        case onAppear
        case onDisappear
        case retryTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                state.messagingState = zappMessaging.latestState()

                return .publisher {
                    zappMessaging.stateStream()
                        .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                        .map(Action.messagingStateChanged)
                }
                .cancellable(id: state.messagingCancelId, cancelInFlight: true)

            case .onDisappear:
                return .cancel(id: state.messagingCancelId)

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                return .none

            case .displayNameChanged(let value):
                state.displayName = UsernameRules.sanitize(value)
                return .none

            case .continueTapped:
                guard state.isValid else { return .none }

                zappMessaging.setDisplayName(state.displayName)
                return .none

            case .retryTapped:
                // Re-queue the name first: the user may have edited it since the failed attempt, and
                // `retryIdentityDerivation` alone would re-derive from the stale one. A boot failure
                // has no name to queue, hence the guard rather than an early return.
                if state.isValid {
                    zappMessaging.setDisplayName(state.displayName)
                }

                zappMessaging.retryIdentityDerivation()
                return .none
            }
        }
    }
}

// MARK: Placeholders

extension ChatIdentitySetup.State {
    static var initial: ChatIdentitySetup.State {
        .init()
    }
}

extension ChatIdentitySetup {
    @MainActor
    static let initial = StoreOf<ChatIdentitySetup>(
        initialState: .initial
    ) {
        ChatIdentitySetup()
    }
}
