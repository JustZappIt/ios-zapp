//
//  NewChatStore.swift
//  Zapp
//
//  Start a conversation: search the saved contacts, or paste a peer's key. Tapping a
//  contact opens a DM; "New group" flips the same list into multi-select.
//
//  Mirrors Android's NewConversation screen, which infers "group" from having selected
//  more than one participant. Here the mode is explicit, so a one-member group is possible.
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
        var errorCode: ZappMessagingFailureCode?
        var didCopy = false

        /// Our own key, so the user can hand it to the person they want to talk
        /// to. Without an exchange in one direction or the other, neither side can
        /// start anything.
        var myPublicKey = ""

        var isGroupMode = false
        var selectedContacts: [ChatContact] = []
        var groupName = ""

        /// The group-name field is only revealed once members are picked, so the CTA
        /// reads "Create group" both before and after it appears.
        var isNamingGroup = false

        /// Non-nil while the "rejoin?" prompt is open, before an explicitly-left DM is recreated.
        @Presents var alert: AlertState<Action>?

        /// Android's `ChatScanPublicKeyScreen`: the camera route into the same field paste uses.
        @Presents var scan: Scan.State?

        var detectedKey: String { PublicKeyRules.sanitize(searchInput) }
        var isValidKey: Bool { PublicKeyRules.isValid(detectedKey) }
        var isOwnKey: Bool {
            isValidKey && detectedKey == PublicKeyRules.sanitize(myPublicKey)
        }

        /// A pasted key we already have a name for.
        var detectedContact: ChatContact? {
            guard isValidKey else { return nil }

            return chatContacts.contact(for: detectedKey)
        }

        /// Blocked contacts are excluded: starting a chat with one silently drops their replies.
        var visibleContacts: [ChatContact] {
            chatContacts.saved.filter {
                !$0.isBlocked && PublicKeyRules.sanitize($0.publicKey) != PublicKeyRules.sanitize(myPublicKey)
            }
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
        /// A group takes keys alone, so the field has no job there.
        var showsNameField: Bool { !isGroupMode && isValidKey && detectedContact == nil }

        var canStart: Bool { isValidKey && !isOwnKey && !isCreating }

        var isDetectedKeySelected: Bool {
            isValidKey && selectedContacts.contains { $0.publicKey == detectedKey }
        }

        var canCreateGroup: Bool { !selectedContacts.isEmpty && !isCreating }

        var canConfirmGroup: Bool {
            canCreateGroup && !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func isSelected(_ contact: ChatContact) -> Bool {
            selectedContacts.contains { $0.publicKey == contact.publicKey }
        }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case peerKeyChanged(String)
        case displayNameChanged(String)
        case pasteTapped
        case scanTapped
        case scan(PresentationAction<Scan.Action>)
        case copyMyKeyTapped
        case copyIndicatorExpired
        case contactTapped(ChatContact)
        case startTapped
        case created(ZMConversation)
        case createFailed(ZappMessagingFailureCode)
        case rejoinRequired(publicKey: String, displayName: String?)
        case rejoinConfirmed(publicKey: String, displayName: String?)
        case alert(PresentationAction<Action>)

        case newGroupTapped
        case detectedKeyAdded
        case participantRemoved(String)
        case groupCreateTapped
        case groupNameChanged(String)
        case groupConfirmTapped
        case groupCancelTapped
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
                state.errorCode = state.isOwnKey ? .ownPublicKey : nil
                return .none

            case .displayNameChanged(let value):
                state.displayName = value
                return .none

            case .pasteTapped:
                guard let pasted = pasteboard.getString() else { return .none }

                return .send(.peerKeyChanged(pasted.data))

                // The checker only accepts a well-formed identity key, so a scanned code either
                // fills the field with something the "start chat" path can use or is ignored.
            case .scanTapped:
                var scanState = Scan.State.initial
                scanState.checkers = [.publicKeyScanChecker]
                state.scan = scanState
                return .none

            case .scan(.presented(.foundString(let key))):
                state.scan = nil
                return .send(.peerKeyChanged(key))

            case .scan(.presented(.cancelTapped)), .scan(.dismiss):
                state.scan = nil
                return .none

            case .scan:
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

            case .contactTapped(let contact):
                guard state.isGroupMode else {
                    return start(&state, publicKey: contact.publicKey, displayName: contact.name)
                }
                guard !state.isCreating else { return .none }

                if let index = state.selectedContacts.firstIndex(where: { $0.publicKey == contact.publicKey }) {
                    state.selectedContacts.remove(at: index)
                } else {
                    state.selectedContacts.append(contact)
                }

                if state.selectedContacts.isEmpty {
                    state.isNamingGroup = false
                }

                return .none

            case .startTapped:
                guard state.isValidKey, !state.isOwnKey else {
                    if state.isOwnKey { state.errorCode = .ownPublicKey }
                    return .none
                }

                let typed = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = state.detectedContact?.name ?? (typed.isEmpty ? nil : typed)
                let key = state.detectedKey

                return start(&state, publicKey: key, displayName: name)

            case .created:
                state.isCreating = false
                state.isGroupMode = false
                state.selectedContacts = []
                state.groupName = ""
                state.isNamingGroup = false
                return .none

            case .createFailed(let code):
                state.isCreating = false
                state.errorCode = code
                return .none

            case let .rejoinRequired(publicKey, displayName):
                state.isCreating = false
                let name = displayName ?? String(publicKey.prefix(Constants.keyPreviewLength))
                state.alert = .rejoinDirect(name: name, publicKey: publicKey, displayName: displayName)
                return .none

            case let .rejoinConfirmed(publicKey, displayName):
                return start(&state, publicKey: publicKey, displayName: displayName, confirmRejoin: false)

            case .alert(.presented(let action)):
                return .send(action)

            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .alert:
                return .none

            case .newGroupTapped:
                guard !state.isCreating, !state.isGroupMode else { return .none }
                state.isGroupMode = true
                state.errorCode = nil
                return .none

            // A pasted key can join a group without ever becoming a saved contact, so the chip
            // is an unsaved stand-in. It is local to this screen and never reaches @Shared.
            case .detectedKeyAdded:
                guard state.isGroupMode, state.isValidKey, !state.isOwnKey, !state.isCreating else {
                    if state.isOwnKey { state.errorCode = .ownPublicKey }
                    return .none
                }

                let key = state.detectedKey
                state.searchInput = ""

                guard !state.selectedContacts.contains(where: { $0.publicKey == key }) else { return .none }

                state.selectedContacts.append(
                    ChatContact(
                        publicKey: key,
                        name: state.chatContacts.contact(for: key)?.name ?? String(key.prefix(Constants.keyPreviewLength)),
                        lastUpdated: .distantPast,
                        isSaved: false
                    )
                )

                return .none

            case .participantRemoved(let publicKey):
                guard !state.isCreating else { return .none }
                state.selectedContacts.removeAll { $0.publicKey == publicKey }

                if state.selectedContacts.isEmpty {
                    state.isNamingGroup = false
                }

                return .none

            case .groupCreateTapped:
                guard state.canCreateGroup else { return .none }
                state.isNamingGroup = true
                return .none

            case .groupNameChanged(let value):
                state.groupName = value
                state.errorCode = nil
                return .none

            case .groupConfirmTapped:
                guard state.canConfirmGroup else { return .none }
                state.isCreating = true
                state.errorCode = nil

                let name = state.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                let keys = state.selectedContacts.map(\.publicKey)

                return .run { send in
                    do {
                        let conversation = try await zappMessaging.createGroup(name, keys)
                        await send(.created(conversation))
                    } catch {
                        LoggerProxy.event("NewChat: createGroup failed: \(error)")
                        await send(.createFailed(ZappMessagingFailureCode(error: error)))
                    }
                }

            case .groupCancelTapped:
                guard !state.isCreating else { return .none }

                if state.isNamingGroup {
                    state.isNamingGroup = false
                    state.groupName = ""
                    return .none
                }

                state.isGroupMode = false
                state.selectedContacts = []
                state.errorCode = nil
                return .none

            case .backToHomeTapped:
                return .none
            }
        }
        .ifLet(\.$scan, action: \.scan) {
            Scan()
        }
    }

    private enum Constants {
        static let keyPreviewLength = 8
    }

    private func start(
        _ state: inout State,
        publicKey: String,
        displayName: String?,
        confirmRejoin: Bool = true
    ) -> Effect<Action> {
        guard !state.isCreating else { return .none }
        state.isCreating = true
        state.errorCode = nil

        return .run { send in
            do {
                // A DM the user explicitly removed is recreated silently once the core clears its
                // tombstone; prompt first so the reappearing thread isn't a surprise. A failed
                // status check falls through to a normal create, matching Android.
                if confirmRejoin, (try? await zappMessaging.hasLeftDirectConversation(publicKey)) == true {
                    await send(.rejoinRequired(publicKey: publicKey, displayName: displayName))
                    return
                }
                let conversation = try await zappMessaging.createDirectConversation(publicKey, displayName)
                await send(.created(conversation))
            } catch {
                LoggerProxy.event("NewChat: createDirectConversation failed: \(error)")
                await send(.createFailed(ZappMessagingFailureCode(error: error)))
            }
        }
    }
}

extension NewChat.State {
    static var initial: NewChat.State { .init() }
}

// MARK: Alerts

extension AlertState where Action == NewChat.Action {
    static func rejoinDirect(name: String, publicKey: String, displayName: String?) -> AlertState {
        AlertState {
            TextState(String(localizable: .newChatRejoinTitle))
        } actions: {
            ButtonState(action: .rejoinConfirmed(publicKey: publicKey, displayName: displayName)) {
                TextState(String(localizable: .newChatRejoinConfirm))
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(String(localizable: .newChatRejoinMessage(name)))
        }
    }
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

    /// Android's scan validator (`ChatScanPublicKeyVM.onScanned`): trim, drop an optional `0x`,
    /// and require what is left to be exactly 64 hex characters — nothing is filtered out.
    ///
    /// `sanitize` must not be used here. Dropping stray characters is a kindness while someone
    /// types or pastes, but applied to a scan it strips a wallet address down to whatever hex
    /// digits it happens to contain: a real 141-character unified address carries 72 of them,
    /// so it would truncate to a 64-character string that passes `isValid` and land in the key
    /// field as a plausible-looking identity that belongs to nobody.
    static func scanned(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unprefixed = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed

        return isValid(unprefixed) ? unprefixed : nil
    }
}
