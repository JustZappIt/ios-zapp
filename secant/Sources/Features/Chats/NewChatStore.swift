//
//  NewChatStore.swift
//  Zapp
//
//  Start a direct conversation from a peer's public key.
//
//  Android's NewConversation screen is a contact search that also detects a
//  pasted key, and supports multi-select for groups. iOS has no chat contacts
//  layer yet, so this is the key-entry half only. Groups and contact search land
//  with that layer.
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct NewChat {
    @ObservableState
    struct State: Equatable {
        var peerKey = ""
        var displayName = ""
        var isCreating = false
        var errorCode: String?
        var didCopy = false

        /// Our own key, so the user can hand it to the person they want to talk
        /// to. Without an exchange in one direction or the other, neither side can
        /// start anything.
        var myPublicKey = ""

        var isValidKey: Bool { PublicKeyRules.isValid(peerKey) }
        var showsInvalidKeyHint: Bool { !peerKey.isEmpty && !isValidKey }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case peerKeyChanged(String)
        case displayNameChanged(String)
        case pasteTapped
        case copyMyKeyTapped
        case copyIndicatorExpired
        case startTapped
        case created(ZMConversation)
        case createFailed(String)
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    private enum CancelID { case copyIndicator }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.myPublicKey = zappMessaging.latestState().identity?.publicKey ?? ""
                return .none

            case .onDisappear:
                return .cancel(id: CancelID.copyIndicator)

            case .peerKeyChanged(let value):
                state.peerKey = PublicKeyRules.sanitize(value)
                state.errorCode = nil
                return .none

            case .displayNameChanged(let value):
                state.displayName = value
                return .none

            case .pasteTapped:
                guard let pasted = pasteboard.getString() else { return .none }
                state.peerKey = PublicKeyRules.sanitize(pasted.data)
                state.errorCode = nil
                return .none

            case .copyMyKeyTapped:
                guard !state.myPublicKey.isEmpty else { return .none }
                pasteboard.setString(RedactableString(state.myPublicKey))
                state.didCopy = true
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyIndicatorExpired)
                }
                .cancellable(id: CancelID.copyIndicator, cancelInFlight: true)

            case .copyIndicatorExpired:
                state.didCopy = false
                return .none

            case .startTapped:
                guard state.isValidKey, !state.isCreating else { return .none }
                state.isCreating = true
                state.errorCode = nil

                let peerKey = state.peerKey
                let name = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

                return .run { send in
                    do {
                        let conversation = try await zappMessaging.createDirectConversation(
                            peerKey,
                            name.isEmpty ? nil : name
                        )
                        await send(.created(conversation))
                    } catch {
                        LoggerProxy.event("NewChat: createDirectConversation failed: \(error)")
                        await send(.createFailed((error as NSError).domain))
                    }
                }

            case .created:
                state.isCreating = false
                return .none

            case .createFailed(let code):
                state.isCreating = false
                state.errorCode = code
                return .none

            case .backToHomeTapped:
                return .none
            }
        }
    }
}

extension NewChat.State {
    static var initial: NewChat.State { .init() }
}

/// An Ed25519 public key as the chat core spells it on the wire: 64 lowercase
/// hex characters. Android accepts an optional `0x` prefix on paste, so we do too.
enum PublicKeyRules {
    static let hexLength = 64

    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unprefixed = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        return String(unprefixed.filter(\.isHexDigit).prefix(hexLength))
    }

    static func isValid(_ key: String) -> Bool {
        key.count == hexLength && key.allSatisfy(\.isHexDigit)
    }
}
