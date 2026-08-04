//
//  SupportChatStore.swift
//  Zapp
//
//  Port of `screen/chat/support/SupportChatVM.kt` + `SupportChatState.kt`.
//
//  A support ticket is an ordinary group conversation with the Zapp support agent, so every call
//  here is one the chat room already makes (`createGroup` / `sendMessage` / `sendMedia` /
//  `removeConversation`). What differs is the SHAPE of the screen: a brand-new ticket opens on a
//  topic picker instead of a composer, and the `[Zapp]:` prefix decides which side a bubble sits
//  on rather than `isFromMe`.
//

import ComposableArchitecture
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import ZappMessaging

@Reducer
struct SupportChat {
    /// What the screen is showing. Mirrors Android's `SupportChatUiState`.
    enum Mode: Equatable {
        case loading
        /// New ticket — no conversation exists until a topic is chosen.
        case selectCategory(isSubmitting: Bool)
        case chat
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        /// `nil` until the topic picker creates the ticket — Android's empty-string args case.
        var conversationId: String?
        var messages: [SupportMessage] = []
        var draft = ""
        var isLoading = true
        var isSubmittingCategory = false
        var sendDidFail = false
        var sendFailureMessage: String?
        var messagingState = ZappMessagingState()

        // Attachments. Android's support composer offers the same media sheet as the chat room;
        // the picker is parked until the sheet is off screen for the reason `ChatRoomAttachments`
        // documents in full.
        var showsMediaSheet = false
        var pendingAttachment: ChatRoom.PendingAttachment?
        var pickedItem: PhotosPickerItem?
        var showsPhotosPicker = false
        var showsFileImporter = false
        var showsCamera = false

        /// Same guard the room carries: blocks a second send while one is in flight.
        var isSendingMedia = false

        var messageReceivedCancelId = UUID()
        var messagingStateCancelId = UUID()

        var mode: Mode {
            if isLoading { return .loading }
            guard conversationId != nil else { return .selectCategory(isSubmitting: isSubmittingCategory) }

            return .chat
        }

        var trimmedDraft: String {
            draft.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var isSendEnabled: Bool { !trimmedDraft.isEmpty }

        init(conversationId: String? = nil) {
            self.conversationId = conversationId
        }

        mutating func insert(_ message: ZMMessage) {
            guard let mapped = SupportMessage.from(message) else { return }
            guard !messages.contains(where: { $0.id == mapped.id }) else { return }

            messages.append(mapped)
            messages.sort { $0.timestamp < $1.timestamp }
        }
    }

    enum Action: Equatable {
        enum Alert: Equatable {
            case leaveConfirmed
        }

        case alert(PresentationAction<Alert>)
        case onAppear
        case onDisappear
        case backTapped
        case categorySelected(SupportCategory)
        case ticketCreated(conversationId: String)
        case ticketCreationFailed
        case messagesLoaded([ZMMessage])
        case messageReceived(ZMMessage)
        case messagingStateChanged(ZappMessagingState)
        case draftChanged(String)
        case sendTapped
        case sendSucceeded(ZMMessage)
        case sendFailed(draft: String)
        case leaveTapped
        case leaveFinished

        // MARK: Media attachments

        case attachTapped
        case mediaSheetDismissed
        case mediaSheetClosed
        case chooseMediaTapped
        case attachFileTapped
        case takePhotoTapped
        case photosPickerDismissed
        case fileImporterDismissed
        case fileImported(URL)
        case cameraAuthorizationResolved(Bool)
        case cameraUnavailable
        case cameraDismissed
        case cameraCaptured(Data)
        case pickedItemChanged(PhotosPickerItem?)
        case mediaSendSucceeded(ZMMessage)
        case mediaSendFailed
        case mediaTooLarge
    }

    @Dependency(\.cameraCapture) var cameraCapture
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        mediaReduce()

        Reduce { state, action in
            switch action {
            case .onAppear:
                let observeState = .publisher {
                    zappMessaging.stateStream()
                        .map(Action.messagingStateChanged)
                } as Effect<Action>

                // A brand-new ticket has nothing to load: the topic picker comes up immediately.
                guard let conversationId = state.conversationId else {
                    state.isLoading = false
                    return observeState.cancellable(id: state.messagingStateCancelId, cancelInFlight: true)
                }

                // A ticket's inbound messages notify and badge like any other conversation, so the
                // room is marked active (and read) while it is on screen — Android's
                // `markActiveWhenConversationKnown`.
                zappMessaging.setActiveConversation(conversationId)

                return .merge(
                    observeState.cancellable(id: state.messagingStateCancelId, cancelInFlight: true),
                    loadTicket(conversationId),
                    observeMessages(in: conversationId, state: state)
                )

            case .onDisappear:
                zappMessaging.setActiveConversation(nil)

                return .merge(
                    .cancel(id: state.messageReceivedCancelId),
                    .cancel(id: state.messagingStateCancelId)
                )

            case .backTapped:
                return .none

                // Creating the ticket is the whole topic picker: a group whose only remote member
                // is the support agent, then the (never-rendered) category marker, then the bot
                // greeting. All three go through calls that already exist — no new wire format.
            case .categorySelected(let category):
                guard state.conversationId == nil, !state.isSubmittingCategory else { return .none }

                state.isSubmittingCategory = true

                return .run { send in
                    let conversation = try await zappMessaging.createGroup(
                        SupportChatConstants.conversationDisplayName(for: category),
                        [SupportChatConstants.supportPublicKey]
                    )

                    _ = try await zappMessaging.sendMessage(
                        conversation.id,
                        SupportChatConstants.categoryMarker(for: category),
                        nil
                    )

                    let greeting = try await zappMessaging.sendMessage(
                        conversation.id,
                        "\(SupportChatConstants.botPrefix)\(category.greeting)",
                        nil
                    )

                    await send(.ticketCreated(conversationId: conversation.id))
                    await send(.messageReceived(greeting))
                } catch: { error, send in
                    LoggerProxy.error("Support chat failed to create ticket: \(error)")
                    await send(.ticketCreationFailed)
                }

            case .ticketCreated(let conversationId):
                state.isSubmittingCategory = false
                state.conversationId = conversationId
                zappMessaging.setActiveConversation(conversationId)

                return observeMessages(in: conversationId, state: state)

            case .ticketCreationFailed:
                state.isSubmittingCategory = false
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .supportChatCreateFailed)
                return .none

            case .messagesLoaded(let messages):
                state.isLoading = false
                state.messages = messages
                    .compactMap(SupportMessage.from)
                    .sorted { $0.timestamp < $1.timestamp }
                return .none

            case .messageReceived(let message):
                state.insert(message)
                return .none

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                return .none

            case .draftChanged(let draft):
                state.draft = draft
                state.sendDidFail = false
                state.sendFailureMessage = nil
                return .none

                // Plain text, unprefixed: only automated messages carry `[Zapp]:`.
            case .sendTapped:
                let content = state.trimmedDraft

                guard !content.isEmpty, let conversationId = state.conversationId else { return .none }

                state.draft = ""
                state.sendDidFail = false
                state.sendFailureMessage = nil

                return .run { send in
                    let message = try await zappMessaging.sendMessage(conversationId, content, nil)
                    await send(.sendSucceeded(message))
                } catch: { error, send in
                    LoggerProxy.error("Support chat failed to send message: \(error)")
                    await send(.sendFailed(draft: content))
                }

            case .sendSucceeded(let message):
                state.insert(message)
                return .none

                // The draft comes back rather than being lost with the failure.
            case .sendFailed(let draft):
                if state.draft.isEmpty {
                    state.draft = draft
                }
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomSendFailed)
                return .none

            case .leaveTapped:
                state.alert = AlertState.closeSupportChat()
                return .none

                // Android posts a bot-prefixed leave notice BEFORE removing the conversation, so
                // the agent's console shows the ticket as closed rather than silently going quiet.
            case .alert(.presented(.leaveConfirmed)):
                guard let conversationId = state.conversationId else {
                    return .send(.leaveFinished)
                }

                return .run { send in
                    do {
                        _ = try await zappMessaging.sendMessage(
                            conversationId,
                            "\(SupportChatConstants.botPrefix)\(String(localizable: .supportChatLeaveNotice))",
                            nil
                        )
                    } catch {
                        LoggerProxy.error("Support chat failed to post leave notice: \(error)")
                    }

                    do {
                        try await zappMessaging.removeConversation(conversationId)
                    } catch {
                        LoggerProxy.error("Support chat failed to close ticket: \(error)")
                    }

                    await send(.leaveFinished)
                }

            case .alert:
                return .none

                // Routed by Root back to the ticket list.
            case .leaveFinished:
                return .none

            default:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    private func loadTicket(_ conversationId: String) -> Effect<Action> {
        .merge(
            .run { _ in
                try await zappMessaging.markRead(conversationId)
            } catch: { error, _ in
                LoggerProxy.error("Support chat mark-read failed: \(error)")
            },
            .run { send in
                let messages = try await zappMessaging.messages(conversationId, supportMessagePageSize)
                await send(.messagesLoaded(messages))
            } catch: { error, send in
                LoggerProxy.error("Support chat failed to load messages: \(error)")
                await send(.messagesLoaded([]))
            }
        )
    }

    private func observeMessages(in conversationId: String, state: State) -> Effect<Action> {
        .publisher {
            zappMessaging.messageReceivedStream()
                .filter { $0.conversationId == conversationId }
                .map(Action.messageReceived)
        }
        .cancellable(id: state.messageReceivedCancelId, cancelInFlight: true)
    }
}

// MARK: - Media attachments

extension SupportChat {
    // One branch per menu action; splitting the switch would scatter the menu rather than
    // simplify it.
    // swiftlint:disable:next cyclomatic_complexity
    func mediaReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .attachTapped:
                state.showsMediaSheet = true
                return .none

            case .mediaSheetDismissed:
                state.showsMediaSheet = false
                return .none

            case .mediaSheetClosed:
                guard let pending = state.pendingAttachment else { return .none }

                state.pendingAttachment = nil

                switch pending {
                case .photos:
                    state.showsPhotosPicker = true
                    return .none

                case .file:
                    state.showsFileImporter = true
                    return .none

                case .camera:
                    return .run { send in
                        guard cameraCapture.isAvailable() else {
                            await send(.cameraUnavailable)
                            return
                        }

                        let granted = cameraCapture.isAuthorized()
                            ? true
                            : await cameraCapture.requestAuthorization()

                        await send(.cameraAuthorizationResolved(granted))
                    }
                }

            case .chooseMediaTapped:
                state.pendingAttachment = .photos
                state.showsMediaSheet = false
                return .none

            case .attachFileTapped:
                state.pendingAttachment = .file
                state.showsMediaSheet = false
                return .none

            case .takePhotoTapped:
                state.pendingAttachment = .camera
                state.showsMediaSheet = false
                return .none

            case .photosPickerDismissed:
                state.showsPhotosPicker = false
                return .none

            case .fileImporterDismissed:
                state.showsFileImporter = false
                return .none

            case .cameraAuthorizationResolved(let granted):
                guard granted else {
                    state.sendDidFail = true
                    state.sendFailureMessage = String(localizable: .chatRoomCameraPermissionRequired)
                    return .none
                }

                state.showsCamera = true
                return .none

            case .cameraUnavailable:
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomCameraUnavailable)
                return .none

            case .cameraDismissed:
                state.showsCamera = false
                return .none

            case .cameraCaptured(let data):
                state.showsCamera = false
                state.sendDidFail = false

                guard let conversationId = state.conversationId, !state.isSendingMedia else { return .none }

                state.isSendingMedia = true

                return .run { send in
                    let encoded = try ChatMediaEncoder.encode(data, supportedTypes: [UTType.jpeg])
                    defer { ChatMediaTemporaryFiles.remove(URL(fileURLWithPath: encoded.path)) }

                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        "",
                        encoded.thumbnail
                    )
                    await send(.mediaSendSucceeded(message))
                } catch: { error, send in
                    LoggerProxy.error("Support chat failed to send camera capture: \(error)")
                    await send(sendFailure(for: error))
                }

            case .fileImported(let url):
                state.showsFileImporter = false
                state.sendDidFail = false

                guard let conversationId = state.conversationId, !state.isSendingMedia else { return .none }

                state.isSendingMedia = true

                return .run { send in
                    let encoded = try ChatFileEncoder.encode(url)
                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        encoded.fileName,
                        encoded.thumbnail
                    )
                    await send(.mediaSendSucceeded(message))
                } catch: { error, send in
                    LoggerProxy.error("Support chat failed to send file: \(error)")
                    await send(sendFailure(for: error))
                }

            case .pickedItemChanged(let item):
                state.pickedItem = nil

                guard let item, let conversationId = state.conversationId, !state.isSendingMedia else { return .none }

                state.sendDidFail = false
                state.isSendingMedia = true
                let supportedTypes = item.supportedContentTypes

                return .run { send in
                    // `ChatPickedMedia` rather than `Data` so a large attachment never has to fit
                    // in memory. Same path the room takes.
                    guard let imported = try await item.loadTransferable(type: ChatPickedMedia.self) else {
                        await send(.mediaSendFailed)
                        return
                    }
                    defer { ChatMediaTemporaryFiles.remove(imported.fileURL) }

                    let encoded = try ChatMediaEncoder.encode(
                        fileURL: imported.fileURL,
                        supportedTypes: supportedTypes
                    )
                    defer { ChatMediaTemporaryFiles.remove(URL(fileURLWithPath: encoded.path)) }

                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        "",
                        encoded.thumbnail
                    )
                    await send(.mediaSendSucceeded(message))
                } catch: { error, send in
                    LoggerProxy.error("Support chat failed to send media: \(error)")
                    await send(sendFailure(for: error))
                }

            case .mediaSendSucceeded(let message):
                state.isSendingMedia = false
                state.sendDidFail = false
                state.sendFailureMessage = nil
                state.insert(message)
                return .none

            case .mediaTooLarge:
                state.isSendingMedia = false
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomGifTooLarge)
                return .none

            case .mediaSendFailed:
                state.isSendingMedia = false
                state.sendDidFail = true
                state.sendFailureMessage = nil
                return .none

            default:
                return .none
            }
        }
    }

    /// Size is the one failure the sender can act on, so it gets its own message.
    private func sendFailure(for error: Error) -> Action {
        (error as? ChatMediaEncoder.Failure) == .tooLarge ? .mediaTooLarge : .mediaSendFailed
    }
}

// MARK: Alerts

extension AlertState where Action == SupportChat.Action.Alert {
    /// Mirrors Android's `support_chat_leave_dialog_*` confirm dialog.
    static func closeSupportChat() -> AlertState {
        AlertState {
            TextState(String(localizable: .supportChatLeaveDialogTitle))
        } actions: {
            ButtonState(role: .destructive, action: .leaveConfirmed) {
                TextState(String(localizable: .supportChatLeaveDialogConfirm))
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(String(localizable: .supportChatLeaveDialogMessage))
        }
    }
}

/// Matches the chat room's page size — a ticket is just a conversation.
private let supportMessagePageSize = 50

// MARK: Placeholders

extension SupportChat.State {
    static var initial: SupportChat.State {
        .init()
    }
}

extension SupportChat {
    @MainActor
    static let initial = StoreOf<SupportChat>(
        initialState: .initial
    ) {
        SupportChat()
    }
}
