//
//  GroupInfoStore.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import ZappMessaging

/// A roster row. Derived from `conversation.participantIds` on every read, never stored: the
/// names come from the contact list, which changes independently of the conversation.
struct GroupMember: Equatable, Identifiable {
    var id: String { publicKey }

    let publicKey: String
    let name: String
    let isOwner: Bool
}

@Reducer
struct GroupInfo {
    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        @Presents var alert: AlertState<Action>?

        /// Seeded by Root and re-seeded from `conversationsStream` after every mutation — the
        /// core is the only authority on who is in the group and what it is called.
        var conversation: ZMConversation

        /// Our own key, so the roster does not list us as one of our own members.
        /// Read from the messaging state, not guessed.
        var localPublicKey = ""

        /// Non-nil while the inline rename field is open.
        var nameDraft: String?

        var isAddMemberPresented = false
        var isMutating = false
        var didFail = false

        var conversationsCancelId = UUID()

        /// The core accepts a rename only from the group's creator. `isOwner` is optional, and a
        /// missing value is not an ownership claim — so nil is treated as "not the owner" and the
        /// control is hidden rather than offered and then failing.
        var canRename: Bool { conversation.isOwner == true }

        var isRenaming: Bool { nameDraft != nil }

        var trimmedNameDraft: String {
            (nameDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var canSaveName: Bool {
            !isMutating
                && !trimmedNameDraft.isEmpty
                && trimmedNameDraft != conversation.displayName
        }

        var members: [GroupMember] {
            let creator = PublicKeyRules.sanitize(conversation.creatorKey ?? "")

            return conversation.participantIds
                .map { PublicKeyRules.sanitize($0) }
                .filter { !$0.isEmpty && $0 != localPublicKey }
                .map { key in
                    GroupMember(
                        publicKey: key,
                        name: memberName(for: key),
                        isOwner: !creator.isEmpty && creator == key
                    )
                }
        }

        /// Everyone we could still add: saved contacts who are neither already in the group,
        /// nor blocked (adding a blocked peer would hide the messages we just invited them to send).
        var addableContacts: [ChatContact] {
            let present = Set(conversation.participantIds.map { PublicKeyRules.sanitize($0) })

            return chatContacts.saved.filter { contact in
                let key = PublicKeyRules.sanitize(contact.publicKey)

                return !contact.isBlocked && !present.contains(key) && key != localPublicKey
            }
        }

        func memberName(for publicKey: String) -> String {
            if let name = chatContacts.contact(for: publicKey)?.name, !name.isEmpty {
                return name
            }

            return String(publicKey.prefix(8))
        }

        init(conversation: ZMConversation) {
            self.conversation = conversation
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case conversationsChanged([ZMConversation])
        case renameTapped
        case nameDraftChanged(String)
        case renameCancelled
        case renameSaveTapped
        case addMemberTapped
        case addMemberDismissed
        case memberSelected(ChatContact)
        case leaveTapped
        case leaveConfirmed
        case mutationFinished
        case mutationFailed
        case alert(PresentationAction<Action>)

        /// We left the group; this screen's subject no longer exists. Root clears the path —
        /// a pushed screen cannot pop itself.
        case didLeave
    }

    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.localPublicKey = PublicKeyRules.sanitize(
                    zappMessaging.latestState().identity?.publicKey ?? ""
                )

                return .publisher {
                    zappMessaging.conversationsStream()
                        .map(Action.conversationsChanged)
                }
                .cancellable(id: state.conversationsCancelId, cancelInFlight: true)

            case .onDisappear:
                return .cancel(id: state.conversationsCancelId)

            // The client re-emits the conversation list after every group mutation, so the roster
            // and the name follow a rename or an add with no refetch. A leave drops the
            // conversation from the list: keep the last good copy rather than blanking the screen
            // in the frame before Root pops it.
            case .conversationsChanged(let conversations):
                guard let updated = conversations.first(where: { $0.id == state.conversation.id }) else {
                    return .none
                }

                state.conversation = updated
                return .none

            case .renameTapped:
                guard state.canRename else { return .none }

                state.nameDraft = state.conversation.displayName
                state.didFail = false
                return .none

            case .nameDraftChanged(let value):
                guard state.nameDraft != nil else { return .none }

                state.nameDraft = value
                state.didFail = false
                return .none

            case .renameCancelled:
                state.nameDraft = nil
                return .none

            case .renameSaveTapped:
                guard state.canRename, state.canSaveName else { return .none }

                let conversationId = state.conversation.id
                let name = state.trimmedNameDraft
                state.nameDraft = nil
                state.isMutating = true
                state.didFail = false

                return .run { send in
                    try await zappMessaging.renameGroup(conversationId, name)
                    await send(.mutationFinished)
                } catch: { error, send in
                    LoggerProxy.error("Group info failed to rename group: \(error)")
                    await send(.mutationFailed)
                }

            case .addMemberTapped:
                state.isAddMemberPresented = true
                state.didFail = false
                return .none

            case .addMemberDismissed:
                state.isAddMemberPresented = false
                return .none

            case .memberSelected(let contact):
                state.isAddMemberPresented = false
                state.isMutating = true
                state.didFail = false

                let conversationId = state.conversation.id
                let publicKey = contact.publicKey
                let name = contact.name.isEmpty ? nil : contact.name

                return .run { send in
                    try await zappMessaging.addMember(conversationId, publicKey, name)
                    await send(.mutationFinished)
                } catch: { error, send in
                    LoggerProxy.error("Group info failed to add member: \(error)")
                    await send(.mutationFailed)
                }

            case .leaveTapped:
                state.alert = AlertState.leaveGroup
                return .none

            case .leaveConfirmed:
                let conversationId = state.conversation.id
                state.isMutating = true
                state.didFail = false

                return .run { send in
                    try await zappMessaging.leaveConversation(conversationId)
                    await send(.didLeave)
                } catch: { error, send in
                    LoggerProxy.error("Group info failed to leave group: \(error)")
                    await send(.mutationFailed)
                }

            case .mutationFinished:
                state.isMutating = false
                return .none

            case .mutationFailed:
                state.isMutating = false
                state.didFail = true
                return .none

            case .alert(.presented(let action)):
                return .send(action)

            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .alert:
                return .none

            case .didLeave:
                state.isMutating = false
                return .none

            case .backToHomeTapped:
                return .none
            }
        }
    }
}

// MARK: Alerts

extension AlertState where Action == GroupInfo.Action {
    static var leaveGroup: AlertState {
        AlertState {
            TextState(String(localizable: .groupLeave))
        } actions: {
            ButtonState(role: .destructive, action: .leaveConfirmed) {
                TextState(String(localizable: .groupLeave))
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(String(localizable: .groupLeaveConfirm))
        }
    }
}

// MARK: Placeholders

extension GroupInfo.State {
    static var initial: GroupInfo.State {
        .init(
            conversation: ZMConversation(
                id: "",
                type: .group,
                participantIds: [],
                displayName: ""
            )
        )
    }
}

extension GroupInfo {
    @MainActor
    static let initial = StoreOf<GroupInfo>(initialState: .initial) {
        GroupInfo()
    }
}
