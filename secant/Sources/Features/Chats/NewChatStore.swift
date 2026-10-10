//
//  NewChatStore.swift
//  Zapp
//
//  Start a conversation: search the saved contacts, scan a QR, or paste a peer's key.
//  Android's NewConversation model: one multi-select screen. Tapping a contact, or adding a
//  pasted, scanned or typed key from the "Public key detected" row, builds participant chips.
//  One chip starts (or reopens) the DM; two or more ask for a group name and create the group.
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct NewChat {
    @ObservableState
    struct State: Equatable {
        /// What the docked button does right now. With nobody picked there is nothing to
        /// start, so the slot advertises the scanner instead of sitting there disabled.
        enum PrimaryAction: Equatable {
            case scan
            case start
        }

        /// Someone picked for the conversation, shown as a chip.
        struct Participant: Equatable, Identifiable {
            let publicKey: String
            /// What the chip reads: the contact's name, or an abbreviated key.
            let name: String
            /// What the core is told to call the peer. Nil for an unsaved pasted key, so the
            /// abbreviated key on the chip never becomes their saved name.
            let displayName: String?

            var id: String { publicKey }
        }

        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        /// Held raw, not sanitized: the one field both searches contacts and takes a
        /// pasted key, so it has to keep the non-hex characters a name search needs.
        var searchInput = ""
        var isCreating = false
        var errorCode: ZappMessagingFailureCode?
        var didCopy = false

        /// Our own key, so the user can hand it to the person they want to talk
        /// to. Without an exchange in one direction or the other, neither side can
        /// start anything.
        var myPublicKey = ""

        var participants: [Participant] = []

        /// The "Name this group" dialog, opened by Start chat with two or more chips. It stays
        /// up while the group is created.
        var isNamingGroup = false
        var groupName = ""

        /// Non-nil while the "rejoin?" prompt is open, before an explicitly-left DM is recreated.
        @Presents var alert: AlertState<Action>?

        /// Non-nil while the QR scanner is up — Android's `ChatScanPublicKeyScreen`, the
        /// camera route into the same field paste uses.
        @Presents var scan: Scan.State?

        /// Shows our own key as a QR the peer can scan — the other half of the exchange.
        var isSharingMyKey = false

        /// Strict: a search string that merely contains 64 hex characters is a search string,
        /// not a peer. See `PublicKeyRules.parse`.
        var detectedKey: String { PublicKeyRules.parse(searchInput) ?? "" }
        var isValidKey: Bool { PublicKeyRules.parse(searchInput) != nil }
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

        /// Android's "Public key detected" row: a complete key that is not already a chip. It
        /// sits right above the search field, so Add is one thumb-reach tap after a paste.
        var showsDetectedKey: Bool { isValidKey && !isDetectedKeySelected }

        /// Our own key is a dead end, so the banner shows it without an Add.
        var canAddDetectedKey: Bool { showsDetectedKey && !isOwnKey && !isCreating }

        /// Nothing to search, nobody picked and nobody to pick: explain the screen instead of
        /// rendering an empty list. Android shows this whenever the field is empty, hiding
        /// saved contacts until something is typed; listing them straight away is kept.
        var showsEmptyState: Bool {
            searchInput.isEmpty && participants.isEmpty && visibleContacts.isEmpty
        }

        /// Stays `.start` while creating, as Android keeps START CHAT (with its spinner)
        /// rather than flipping back to the scanner mid-create. A complete key in the field
        /// that isn't a chip yet also starts: the chat it names is the one meant.
        var primaryAction: PrimaryAction {
            participants.isEmpty && !canAddDetectedKey && !isCreating ? .scan : .start
        }

        var isPrimaryEnabled: Bool { !isCreating }

        var isDetectedKeySelected: Bool {
            isValidKey && participants.contains { $0.publicKey == detectedKey }
        }

        var canConfirmGroup: Bool {
            participants.count > 1 && !isCreating && !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func isSelected(_ contact: ChatContact) -> Bool {
            participants.contains { $0.publicKey == contact.publicKey }
        }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case peerKeyChanged(String)
        case pasteTapped
        case searchCleared
        case copyMyKeyTapped
        case copyIndicatorExpired
        case contactTapped(ChatContact)
        case detectedKeyAdded
        case participantRemoved(String)
        case startTapped
        case primaryTapped
        case scanTapped
        case scan(PresentationAction<Scan.Action>)
        case shareMyKeyTapped
        case shareMyKeyDismissed
        case created(ZMConversation)
        case createFailed(ZappMessagingFailureCode)
        case rejoinRequired(publicKey: String, displayName: String?)
        case rejoinConfirmed(publicKey: String, displayName: String?)
        case alert(PresentationAction<Action>)

        case groupNameChanged(String)
        case groupConfirmTapped
        case groupCancelTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    private enum CancelID { case copyIndicator }

    /// A pasted key can join without ever becoming a saved contact, so the chip is an unsaved
    /// stand-in. It is local to this screen and never reaches @Shared.
    private func addDetectedKey(_ state: inout State) {
        let key = state.detectedKey
        let name = state.detectedContact?.name

        state.participants.append(
            State.Participant(
                publicKey: key,
                name: name ?? String(key.prefix(Constants.keyPreviewLength)),
                displayName: name
            )
        )
        state.searchInput = ""
        state.errorCode = nil
    }

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

            case .pasteTapped:
                guard let pasted = pasteboard.getString() else { return .none }

                return .send(.peerKeyChanged(pasted.data))

            case .searchCleared:
                state.searchInput = ""
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

            case .contactTapped(let contact):
                guard !state.isCreating else { return .none }

                if state.isSelected(contact) {
                    state.participants.removeAll { $0.publicKey == contact.publicKey }
                } else {
                    state.participants.append(
                        State.Participant(publicKey: contact.publicKey, name: contact.name, displayName: contact.name)
                    )
                }
                state.errorCode = nil
                return .none

            // Add on the "Public key detected" row: the key becomes a chip and the field clears
            // for the next person, so a group can be built from several pasted keys.
            case .detectedKeyAdded:
                guard state.canAddDetectedKey else {
                    if state.isOwnKey { state.errorCode = .ownPublicKey }
                    return .none
                }

                addDetectedKey(&state)
                return .none

            case .participantRemoved(let publicKey):
                guard !state.isCreating else { return .none }
                state.participants.removeAll { $0.publicKey == publicKey }
                return .none

            case .startTapped:
                // A key pasted or scanned but not added yet joins the chat it starts.
                if state.canAddDetectedKey {
                    addDetectedKey(&state)
                }
                guard !state.isCreating, let first = state.participants.first else { return .none }

                // More than one participant is a group, which needs a name before it exists.
                // The dialog shows a create failure from `errorCode`, so an older error (an own
                // key pasted earlier, a failed DM) must not greet it.
                guard state.participants.count == 1 else {
                    state.groupName = ""
                    state.errorCode = nil
                    state.isNamingGroup = true
                    return .none
                }

                return start(&state, publicKey: first.publicKey, displayName: first.displayName)

            case .primaryTapped:
                switch state.primaryAction {
                case .scan: return .send(.scanTapped)
                case .start: return .send(.startTapped)
                }

            case .scanTapped:
                guard !state.isCreating else { return .none }
                var scanState = Scan.State()
                scanState.checkers = [.chatPublicKeyScanChecker]
                scanState.instructions = String(localizable: .newChatScanInstructions)
                state.scan = scanState
                return .none

                // The scanner only ever hands back a sanitized 64-hex key, so it lands in
                // the same field a paste would and the detected-key row takes over.
            case .scan(.presented(.foundString(let key))):
                state.scan = nil
                return .send(.peerKeyChanged(key))

            case .scan(.presented(.cancelTapped)), .scan(.dismiss):
                state.scan = nil
                return .none

            case .scan:
                return .none

            case .shareMyKeyTapped:
                guard !state.myPublicKey.isEmpty else { return .none }
                state.isSharingMyKey = true
                return .none

            case .shareMyKeyDismissed:
                state.isSharingMyKey = false
                return .none

            case .created:
                state.isCreating = false
                state.participants = []
                state.groupName = ""
                state.isNamingGroup = false
                return .none

            // A failed group create keeps the naming dialog up, with the failure in it, so the
            // name is not lost to a retry.
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

            case .groupNameChanged(let value):
                state.groupName = value
                state.errorCode = nil
                return .none

            case .groupConfirmTapped:
                guard state.canConfirmGroup else { return .none }
                state.isCreating = true
                state.errorCode = nil

                let name = state.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                let keys = state.participants.map(\.publicKey)

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
                state.isNamingGroup = false
                state.groupName = ""
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

    private static let previewHead = 12
    private static let previewTail = 6

    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unprefixed = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        return String(unprefixed.filter(\.isHexDigit).prefix(hexLength))
    }

    static func isValid(_ key: String) -> Bool {
        key.count == hexLength && key.allSatisfy(\.isHexDigit)
    }

    /// Strict counterpart to `sanitize`, for deciding whether some untrusted text *is* a key
    /// rather than coercing it into one. Android's scan validator
    /// (`ChatScanPublicKeyVM.onScanned`) applies the same rule.
    ///
    /// `sanitize` drops every non-hex character and truncates to 64, which is right for
    /// masking a field as it is typed but wrong for validation: a URL or a sentence with
    /// enough incidental hex in it silently becomes a well-formed key for a peer who does not
    /// exist. A wallet address is the worst case — a real 141-character unified address carries
    /// 72 hex digits, so `sanitize` would truncate it to a 64-character string that passes
    /// `isValid` and land in the key field as a plausible-looking identity belonging to nobody.
    /// Here anything other than whitespace and an optional `0x` disqualifies the input.
    ///
    /// Whitespace is dropped anywhere, not just at the ends, because keys are routinely copied
    /// out of a wrapped display. Matches Android, which also requires the cleaned string to be
    /// the key in its entirety.
    static func parse(_ raw: String) -> String? {
        let compact = raw.filter { !$0.isWhitespace }.lowercased()
        let unprefixed = compact.hasPrefix("0x") ? String(compact.dropFirst(2)) : compact

        return isValid(unprefixed) ? unprefixed : nil
    }

    /// Head-and-tail form for display, as Android abbreviates it. Both ends are kept: the
    /// tail is what someone reads back to confirm they pasted the right key.
    static func abbreviated(_ key: String) -> String {
        guard key.count > previewHead + previewTail else { return key }

        return "\(key.prefix(previewHead))…\(key.suffix(previewTail))"
    }
}
