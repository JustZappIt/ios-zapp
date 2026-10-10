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

        /// Android shows the name rules only once a submit fails them, not as a standing caption.
        var showsNameRulesError = false

        var isValid: Bool { UsernameRules.isValid(displayName) }

        /// Android's `isSubmitting`: the name is in and the identity is being derived.
        var isSubmitting: Bool { messagingState.phase == .deriving }

        /// A failed derive and a failed worklet boot land the form in the same shape: message, raw
        /// code, retry. They differ only in where the subsystem parks the code.
        var errorCode: String? {
            if case .failed(let code) = messagingState.phase {
                return code
            }

            return messagingState.identityErrorCode
        }

        /// What "Copy error details" puts on the clipboard, Android's `buildSetupDiagnostic`.
        var diagnostic: String? {
            errorCode.map { ChatIdentitySetup.diagnostic(operation: "chat-identity setup", code: $0) }
        }

        init() { }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<ChatIdentitySetup.State>)
        case continueTapped
        case copyErrorDetailsTapped
        case displayNameChanged(String)
        case messagingStateChanged(ZappMessagingState)
        case onAppear
        case onDisappear
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pasteboard) var pasteboard
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
                state.showsNameRulesError = false
                return .none

            // Android's `onSubmit`: an invalid name explains the rules; a valid one is handed over,
            // and a previous failed derive is retried, since an unchanged name would not re-fire.
            case .continueTapped:
                // A worklet boot failure has no name to wait for: retry the boot as it stands.
                if case .failed = state.messagingState.phase, !state.isValid {
                    zappMessaging.retryIdentityDerivation()
                    return .none
                }

                guard state.isValid else {
                    state.showsNameRulesError = true
                    return .none
                }

                state.showsNameRulesError = false
                zappMessaging.setDisplayName(state.displayName)
                if state.errorCode != nil {
                    zappMessaging.retryIdentityDerivation()
                }
                return .none

            case .copyErrorDetailsTapped:
                guard let diagnostic = state.diagnostic else { return .none }

                pasteboard.setString(RedactableString(diagnostic))
                return .none
            }
        }
    }
}

extension ChatIdentitySetup {
    static func diagnostic(operation: String, code: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""

        return """
        Zapp setup error
        when: \(operation)
        code: \(code)
        build: \(version) (\(build)) iOS
        """
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
