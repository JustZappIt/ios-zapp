//
//  NewChatStore.swift
//  Zapp
//
//  Start a direct conversation: search the saved contacts, or paste a peer's key.
//
//  Mirrors Android's NewConversation screen, minus its multi-select group path —
//  `createGroup` has no surface on `ZappMessagingClient` yet.
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct NewChat {
    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        /// Held raw, not sanitized: the one field both searches contacts and takes a
        /// pasted key, so it has to keep the non-hex characters a name search needs.
        var searchInput = ""
        var displayName = ""
        var isCreating = false
        var errorCode: String?
        var didCopy = false

        /// Our own key, so the user can hand it to the person they want to talk
        /// to. Without an exchange in one direction or the other, neither side can
        /// start anything.
        var myPublicKey = ""

        var detectedKey: String { PublicKeyRules.sanitize(searchInput) }
        var isValidKey: Bool { PublicKeyRules.isValid(detectedKey) }

        /// A pasted key we already have a name for.
        var detectedContact: ChatContact? {
            guard isValidKey else { return nil }

            return chatContacts.contact(for: detectedKey)
        }

        /// Blocked contacts are excluded: starting a chat with one silently drops their replies.
        var visibleContacts: [ChatContact] {
            chatContacts.saved.filter { !$0.isBlocked }
        }

        var filteredContacts: [ChatContact] {
            let query = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !query.isEmpty else { return visibleContacts }

            return visibleContacts.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.publicKey.localizedCaseInsensitiveContains(query)
            }
        }

        /// Only an unknown pasted key needs a name; a saved contact already has one.
        var showsNameField: Bool { isValidKey && detectedContact == nil }

        var canStart: Bool { isValidKey && !isCreating }

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
        case contactTapped(ChatContact)
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
                state.searchInput = value
                state.errorCode = nil
                return .none

            case .displayNameChanged(let value):
                state.displayName = value
                return .none

            case .pasteTapped:
                guard let pasted = pasteboard.getString() else { return .none }

                return .send(.peerKeyChanged(pasted.data))

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

            case .contactTapped(let contact):
                return start(&state, publicKey: contact.publicKey, displayName: contact.name)

            case .startTapped:
                guard state.isValidKey else { return .none }

                let typed = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = state.detectedContact?.name ?? (typed.isEmpty ? nil : typed)
                let key = state.detectedKey

                return start(&state, publicKey: key, displayName: name)

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

    private func start(
        _ state: inout State,
        publicKey: String,
        displayName: String?
    ) -> Effect<Action> {
        guard !state.isCreating else { return .none }
        state.isCreating = true
        state.errorCode = nil

        return .run { send in
            do {
                let conversation = try await zappMessaging.createDirectConversation(publicKey, displayName)
                await send(.created(conversation))
            } catch {
                LoggerProxy.event("NewChat: createDirectConversation failed: \(error)")
                await send(.createFailed((error as NSError).domain))
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
