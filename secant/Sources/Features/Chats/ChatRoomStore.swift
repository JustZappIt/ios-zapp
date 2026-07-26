//
//  ChatRoomStore.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZappMessaging

@Reducer
struct ChatRoom {
    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        /// Share-address posts THIS account's unified address, matching Android's
        /// `getZashiAccount().unified.address.address` — never a hardware-wallet account.
        @Shared(.inMemory(.zashiWalletAccount)) var zashiWalletAccount: WalletAccount?

        /// Drives the fiat side of payment-request bubbles and the split sheet, the way
        /// Android feeds its `ZecFiatRate` in from `exchangeRateRepository`.
        @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion?

        var conversationId: String
        var conversation: ZMConversation?
        var messages: [ZMMessage] = []
        var draft = ""
        var isLoading = true
        var sendDidFail = false
        var sendFailureMessage: String?
        var messagingState = ZappMessagingState()
        var showsNetworkDetails = false
        var isLoadingNetworkDetails = false
        var connectionDetails: ZMConnectionDetails?

        var replyingTo: ZMMessage?

        /// Held so a failed send can hand the quote back with the draft.
        var pendingReply: ZMMessage?

        /// Bound to the composer's `PhotosPicker`. Consumed and cleared the moment it lands.
        var pickedItem: PhotosPickerItem?

        // Composer attachment menu. See `ChatRoomAttachments.swift`.
        var showsAttachmentSheet = false
        var attachmentPage: ChatRoom.AttachmentPage = .actions
        var pendingAttachment: ChatRoom.PendingAttachment?
        var showsPhotosPicker = false
        var showsFileImporter = false
        var showsCamera = false

        /// Split bill / request payment. See `ChatSplitBillStore.swift`.
        var splitBill: SplitBillState?

        /// The media message opened fullscreen, if any. See `ChatImageViewer.swift`.
        var imageViewerMessage: ZMMessage?

        /// Add / edit / block the peer, opened from the DM's title. Android's `openEditSheet`.
        @Presents var contactForm: ChatContactForm.State?

        /// mediaId -> 0...1 while a transfer is in flight.
        var mediaProgress: [String: Double] = [:]
        var completedMediaIds: Set<String> = []

        /// A delivery status can arrive before the message it belongs to is in `messages`:
        /// the core acks faster than `sendMessage` returns. Hold it until the message shows up,
        /// or the first tick is lost until a cold reload.
        var earlyStatuses: [String: String] = [:]

        var messageReceivedCancelId = UUID()
        var messagingStateCancelId = UUID()
        var messageStatusCancelId = UUID()
        var mediaProgressCancelId = UUID()
        var mediaCompleteCancelId = UUID()

        var trimmedDraft: String {
            draft.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var title: String {
            guard let conversation else { return String(localizable: .chatRoomTitleFallback) }

            let name = conversation.resolvedDisplayName(chatContacts)

            return name.isEmpty ? String(localizable: .chatRoomTitleFallback) : name
        }

        /// Blocked senders are filtered on the way out too, not just at ingest: a
        /// cold load reads straight from the store, which knows nothing about blocks.
        var isGroup: Bool { conversation?.type == .group }

        var visibleMessages: [ZMMessage] {
            messages.filter { !chatContacts.isBlocked($0.senderId) }
        }

        /// Requests settled by a `zec-transaction` receipt somewhere in this room. Android
        /// recomputes the same set per render (`paidRequestIds`); the settlement is derived from
        /// the message log rather than stored, so it survives a cold reload on both platforms.
        var paidRequestIds: Set<String> {
            ChatPaymentSettlement.paidRequestIds(in: messages)
        }

        /// Decides whether a payment request naming a debtor is ours to pay.
        var localPublicKey: String? {
            messagingState.identity?.publicKey
        }

        func senderName(for message: ZMMessage) -> String? {
            message.resolvedSenderName(chatContacts)
        }

        /// `ZMReplyContext.senderName` is not optional and the quote is denormalised at send
        /// time, so an unnamed sender has to resolve to something. Our own name comes from our
        /// identity rather than a "You" literal — there is no such string in the catalogue.
        func replySenderName(for message: ZMMessage) -> String {
            if message.isFromMe {
                return message.senderName
                    ?? messagingState.identity?.displayName
                    ?? String(localizable: .generalUnknown)
            }

            return senderName(for: message) ?? String(localizable: .generalUnknown)
        }

        /// The header pill owns peer presence and transport detail. Keep the
        /// subtitle quiet while our node is connected; when it is offline there
        /// cannot be a reachable peer, so saying so here is still useful.
        var subtitle: String? {
            messagingState.isOnline ? nil : String(localizable: .chatRoomPeerOffline)
        }

        init(conversationId: String, conversation: ZMConversation? = nil) {
            self.conversationId = conversationId
            self.conversation = conversation
        }

        mutating func insert(_ message: ZMMessage) {
            guard !messages.contains(where: { $0.id == message.id }) else { return }

            messages.append(message)
            messages.sort { $0.timestamp < $1.timestamp }

            guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }

            applyEarlyStatus(at: index)
        }

        mutating func applyEarlyStatus(at index: Int) {
            let message = messages[index]

            guard let early = earlyStatuses.removeValue(forKey: message.id) else { return }

            messages[index] = message.withStatus(ChatMessageStatusOrder.advance(from: message.status, to: early))
        }

        mutating func rememberEarlyStatus(_ messageId: String, _ status: String) {
            earlyStatuses[messageId] = ChatMessageStatusOrder.advance(from: earlyStatuses[messageId], to: status)

            while earlyStatuses.count > maxEarlyStatuses, let oldest = earlyStatuses.keys.first {
                earlyStatuses.removeValue(forKey: oldest)
            }
        }

        mutating func reconcile(clientId: String, with persisted: ZMMessage) {
            let echoedStatus = messages.first(where: { $0.id == persisted.id })?.status
            messages.removeAll { $0.id == clientId || $0.id == persisted.id }

            if let echoedStatus {
                insert(
                    persisted.withStatus(
                        ChatMessageStatusOrder.advance(from: persisted.status, to: echoedStatus)
                    )
                )
            } else {
                insert(persisted)
            }
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case titleTapped
        case draftChanged(String)
        case sendTapped
        case sendSucceeded(clientId: String, message: ZMMessage)
        case messagesLoaded([ZMMessage])
        case messageReceived(ZMMessage)
        case messagingStateChanged(ZappMessagingState)
        case networkChipTapped
        case networkDetailsDismissed
        case networkDetailsLoaded(ZMConnectionDetails)
        case networkDetailsFailed
        case sendFailed(clientId: String, code: ZappMessagingFailureCode)
        case retrySendTapped(ZMMessage)
        case replyTapped(ZMMessage)
        case cancelReplyTapped
        case pickedItemChanged(PhotosPickerItem?)
        case mediaSendFailed
        case messageStatusChanged(messageId: String, status: String)
        case mediaProgressChanged(mediaId: String, progress: Double)
        case mediaCompleted(mediaId: String, filePath: String)

        // MARK: Attachment menu — reduced in `ChatRoomAttachments.swift`

        case attachTapped
        case attachmentSheetDismissed
        case attachmentSheetClosed
        case attachMediaTapped
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
        case shareAddressTapped
        case shareAddressFailed
        /// Routed by Root into `SendCoordFlow`, prefilled with the peer's address.
        case sendZecTapped
        /// Routed by Root into `ScanCoordFlow`.
        case scanWalletAddressTapped

        // MARK: Split bill — reduced in `ChatSplitBillStore.swift`

        case splitBillTapped
        case splitSheetDismissed
        case splitTotalChanged(String)
        case splitMemoChanged(String)
        case splitShareChanged(publicKey: String, text: String)
        case splitCurrencyToggled
        case splitSendTapped
        case splitSendFailed

        // MARK: Rich bubbles

        /// A payment request the user chose to pay. Routed by Root into `SendCoordFlow`,
        /// prefilled with the requester's address and amount.
        case payRequestTapped(ZMMessage)
        /// Routed by Root into the transaction detail — only when the tx is in this wallet.
        case viewTransactionTapped(String)
        /// A shared wallet-address bubble tapped into a send. Routed by Root.
        case sendToAddressTapped(String)
        case copyAddressTapped(String)
        /// The peer's tx id is not in this wallet yet, so there is no detail to open.
        case transactionUnavailable
        case imageTapped(ZMMessage)
        case imageViewerDismissed
        case contactForm(PresentationAction<ChatContactForm.Action>)

        /// Handed up to Root, which owns the shared contacts projection.
        case contactsChanged(ChatContacts)
    }

    @Dependency(\.cameraCapture) var cameraCapture
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        attachmentReduce()
        splitBillReduce()

        Reduce { state, action in
            switch action {
            case .onAppear:
                let conversationId = state.conversationId
                zappMessaging.setActiveConversation(conversationId)

                return .merge(
                    .run { _ in
                        try await zappMessaging.markRead(conversationId)
                    } catch: { error, _ in
                        LoggerProxy.error("Chat room mark-read failed: \(error)")
                    },
                    .run { send in
                        let messages = try await zappMessaging.messages(conversationId, messagePageSize)
                        await send(.messagesLoaded(messages))
                    } catch: { error, send in
                        LoggerProxy.error("Chat room failed to load messages: \(error)")
                        await send(.messagesLoaded([]))
                    },
                    .publisher {
                        zappMessaging.messageReceivedStream()
                            .filter { $0.conversationId == conversationId }
                            .map(Action.messageReceived)
                    }
                    .cancellable(id: state.messageReceivedCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.stateStream()
                            .map(Action.messagingStateChanged)
                    }
                    .cancellable(id: state.messagingStateCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.messageStatusStream()
                            .filter { $0.conversationId == conversationId }
                            .map { Action.messageStatusChanged(messageId: $0.messageId, status: $0.status) }
                    }
                    .cancellable(id: state.messageStatusCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.mediaProgressStream()
                            .map { Action.mediaProgressChanged(mediaId: $0.mediaId, progress: $0.progress) }
                    }
                    .cancellable(id: state.mediaProgressCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.mediaCompleteStream()
                            .map { Action.mediaCompleted(mediaId: $0.mediaId, filePath: $0.filePath) }
                    }
                    .cancellable(id: state.mediaCompleteCancelId, cancelInFlight: true)
                )

            case .onDisappear:
                zappMessaging.setActiveConversation(nil)

                return .merge(
                    .cancel(id: state.messageReceivedCancelId),
                    .cancel(id: state.messagingStateCancelId),
                    .cancel(id: state.messageStatusCancelId),
                    .cancel(id: state.mediaProgressCancelId),
                    .cancel(id: state.mediaCompleteCancelId)
                )

            case .backToHomeTapped:
                return .none

            // A group's title is routed by Root into group info. A DM's title opens the peer's
            // contact record instead — add when they are unknown, edit when they are saved —
            // which is also where Block/Unblock lives. Mirrors Android's `onTitleClick`.
            case .titleTapped:
                guard !state.isGroup, let publicKey = state.peerPublicKey else { return .none }

                let existing = state.chatContacts.contact(for: publicKey)
                state.contactForm = ChatContactForm.State(
                    existing: existing?.isSaved == true ? existing : nil,
                    prefill: existing ?? ChatContact(
                        publicKey: publicKey,
                        name: state.conversation?.resolvedDisplayName(state.chatContacts) ?? "",
                        address: state.resolvedPeerWalletAddress ?? "",
                        isSaved: false
                    )
                )
                return .none

            case .contactForm(.presented(.delegate(.contactsChanged(let contacts)))):
                state.contactForm = nil
                return .send(.contactsChanged(contacts))

            case .contactForm(.presented(.closeTapped)):
                state.contactForm = nil
                return .none

            case .contactForm, .contactsChanged:
                return .none

            case .draftChanged(let draft):
                state.draft = draft
                state.sendDidFail = false
                state.sendFailureMessage = nil
                return .none

            case .sendTapped:
                let content = state.trimmedDraft
                guard !content.isEmpty else { return .none }

                let replyTo = state.replyingTo
                let reply = replyTo.map {
                    ZMReplyContext(
                        id: $0.id,
                        senderName: state.replySenderName(for: $0),
                        content: String($0.content.prefix(replyPreviewMaxLength))
                    )
                }

                state.draft = ""
                state.sendDidFail = false
                state.sendFailureMessage = nil
                state.replyingTo = nil
                state.pendingReply = replyTo
                let conversationId = state.conversationId
                let clientId = "local_\(UUID().uuidString)"

                state.insert(
                    ZMMessage(
                        id: clientId,
                        conversationId: conversationId,
                        senderId: state.messagingState.identity?.publicKey ?? "",
                        senderName: state.messagingState.identity?.displayName,
                        content: content,
                        contentType: ChatContentType.text,
                        timestamp: Date(),
                        isFromMe: true,
                        status: "sending",
                        replyToId: reply?.id,
                        replyToSenderName: reply?.senderName,
                        replyToContent: reply?.content
                    )
                )

                return .run { send in
                    let message = try await zappMessaging.sendMessage(conversationId, content, reply)
                    await send(.sendSucceeded(clientId: clientId, message: message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send message: \(error)")
                    await send(
                        .sendFailed(
                            clientId: clientId,
                            code: ZappMessagingFailureCode(error: error)
                        )
                    )
                }

            case .sendSucceeded(let clientId, let message):
                state.pendingReply = nil
                state.sendDidFail = false
                state.sendFailureMessage = nil
                state.reconcile(clientId: clientId, with: message)
                return .none

            case .messagesLoaded(let messages):
                state.isLoading = false
                state.messages = messages.sorted { $0.timestamp < $1.timestamp }

                for index in state.messages.indices {
                    state.applyEarlyStatus(at: index)
                }

                return .none

            case .messageReceived(let message):
                guard !state.chatContacts.isBlocked(message.senderId) else { return .none }

                if message.isFromMe {
                    state.pendingReply = nil
                }

                state.insert(message)
                return .none

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                return .none

            case .networkChipTapped:
                state.showsNetworkDetails = true
                state.isLoadingNetworkDetails = true
                return loadNetworkDetails()

            case .networkDetailsDismissed:
                state.showsNetworkDetails = false
                return .none

            case .networkDetailsLoaded(let details):
                state.connectionDetails = details
                state.isLoadingNetworkDetails = false
                return .none

            case .networkDetailsFailed:
                state.connectionDetails = nil
                state.isLoadingNetworkDetails = false
                return .none

            case .sendFailed(let clientId, let code):
                if let index = state.messages.firstIndex(where: { $0.id == clientId }) {
                    state.messages[index] = state.messages[index].withStatus("failed")
                }
                state.pendingReply = nil
                state.sendDidFail = true
                state.sendFailureMessage = code == .ownPublicKey || code == .ipc(.ownPublicKey)
                    ? String(localizable: .chatRoomOwnKeySendFailed)
                    : String(localizable: .chatRoomSendFailed)
                return .none

            case .retrySendTapped(let failedMessage):
                guard failedMessage.isFromMe,
                      failedMessage.status == "failed",
                      let index = state.messages.firstIndex(where: { $0.id == failedMessage.id })
                else { return .none }

                let reply = failedMessage.replyToId.map {
                    ZMReplyContext(
                        id: $0,
                        senderName: failedMessage.replyToSenderName ?? String(localizable: .generalUnknown),
                        content: failedMessage.replyToContent ?? ""
                    )
                }
                state.messages[index] = failedMessage.withStatus("sending")
                state.sendDidFail = false
                state.sendFailureMessage = nil

                return .run { send in
                    let message = try await zappMessaging.sendMessage(
                        failedMessage.conversationId,
                        failedMessage.content,
                        reply
                    )
                    await send(.sendSucceeded(clientId: failedMessage.id, message: message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to retry message: \(error)")
                    await send(
                        .sendFailed(
                            clientId: failedMessage.id,
                            code: ZappMessagingFailureCode(error: error)
                        )
                    )
                }

            case .replyTapped(let message):
                state.replyingTo = message
                return .none

            case .cancelReplyTapped:
                state.replyingTo = nil
                return .none

            case .pickedItemChanged(let item):
                state.pickedItem = nil

                guard let item else { return .none }

                state.sendDidFail = false
                let conversationId = state.conversationId

                return .run { send in
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        await send(.mediaSendFailed)
                        return
                    }

                    let encoded = try ChatMediaEncoder.encode(data, supportedTypes: item.supportedContentTypes)
                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        "",
                        encoded.thumbnail
                    )
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send media: \(error)")
                    await send(.mediaSendFailed)
                }

            case .mediaSendFailed:
                state.sendDidFail = true
                state.sendFailureMessage = nil
                return .none

            case .messageStatusChanged(let messageId, let status):
                guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else {
                    state.rememberEarlyStatus(messageId, status)
                    return .none
                }

                let message = state.messages[index]
                state.messages[index] = message.withStatus(
                    ChatMessageStatusOrder.advance(from: message.status, to: status)
                )
                return .none

            // A straggler <1.0 event after completion must not re-insert the id and strand a
            // permanent progress bar; a completed id is final.
            case .mediaProgressChanged(let mediaId, let progress):
                guard !state.completedMediaIds.contains(mediaId) else { return .none }

                if progress >= 1 {
                    state.completedMediaIds.insert(mediaId)
                    state.mediaProgress.removeValue(forKey: mediaId)
                } else {
                    state.mediaProgress[mediaId] = progress
                }

                return .none

            case .mediaCompleted(let mediaId, let filePath):
                state.completedMediaIds.insert(mediaId)
                state.mediaProgress.removeValue(forKey: mediaId)

                for index in state.messages.indices
                where state.messages[index].mediaId == mediaId && state.messages[index].mediaLocalPath == nil {
                    state.messages[index].mediaLocalPath = filePath
                }

                return .none

            case .imageTapped(let message):
                state.imageViewerMessage = message
                return .none

            case .imageViewerDismissed:
                state.imageViewerMessage = nil
                return .none

            case .copyAddressTapped(let address):
                pasteboard.setString(RedactableString(address))
                return .none

            // Android toasts; the room's inline strip is iOS's equivalent transient surface, and
            // it is already where every other chat failure is reported.
            case .transactionUnavailable:
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomTransactionNotSynced)
                return .none

            // Routed by Root — the room only clears its own transient state.
            case .payRequestTapped, .sendToAddressTapped, .viewTransactionTapped:
                state.sendDidFail = false
                state.sendFailureMessage = nil
                return .none

            // Owned by `attachmentReduce()`, which runs first.
            case .attachTapped, .attachmentSheetDismissed, .attachmentSheetClosed, .attachMediaTapped,
                .chooseMediaTapped, .attachFileTapped, .takePhotoTapped, .photosPickerDismissed,
                .fileImporterDismissed, .fileImported, .cameraAuthorizationResolved, .cameraUnavailable,
                .cameraDismissed, .cameraCaptured, .shareAddressTapped, .shareAddressFailed,
                .sendZecTapped, .scanWalletAddressTapped:
                return .none

            // Owned by `splitBillReduce()`, which runs first.
            case .splitBillTapped, .splitSheetDismissed, .splitTotalChanged, .splitMemoChanged,
                .splitShareChanged, .splitCurrencyToggled, .splitSendTapped, .splitSendFailed:
                return .none
            }
        }
        .ifLet(\.$contactForm, action: \.contactForm) {
            ChatContactForm()
        }
    }

    private func loadNetworkDetails() -> Effect<Action> {
        .run { send in
            let details = try await zappMessaging.connectionDetails()
            await send(.networkDetailsLoaded(details))
        } catch: { error, send in
            LoggerProxy.error("Chat room failed to load network details: \(error)")
            await send(.networkDetailsFailed)
        }
    }
}

private let messagePageSize = 50
private let replyPreviewMaxLength = 100
private let maxEarlyStatuses = 64

/// Delivery state only ever moves forward. Without this a late `sent` overwrites a `read`
/// double-tick, and the mark walks backwards while the user watches.
enum ChatMessageStatusOrder {
    static func advance(from current: String?, to next: String) -> String {
        switch current {
        case "read": return "read"
        case "failed": return "failed"
        default: break
        }

        if next == "failed" || next == "read" { return next }
        if current == "sent" { return "sent" }
        if current == "queued", next == "sending" { return "queued" }

        return next
    }
}

extension ZMMessage {
    /// `status` is a `let` on the SDK model, so a delivery update rebuilds the value.
    func withStatus(_ status: String) -> ZMMessage {
        ZMMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            senderName: senderName,
            content: content,
            contentType: contentType,
            timestamp: timestamp,
            isFromMe: isFromMe,
            mediaId: mediaId,
            mediaSize: mediaSize,
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight,
            thumbnailData: thumbnailData,
            mediaLocalPath: mediaLocalPath,
            mediaTransferState: mediaTransferState,
            status: status,
            replyToId: replyToId,
            replyToSenderName: replyToSenderName,
            replyToContent: replyToContent
        )
    }
}

/// Turns a picked photo into something the core can ship: a file on disk, a MIME type the peer
/// can actually decode, and a wire thumbnail small enough to ride inside the message body.
enum ChatMediaEncoder {
    struct Encoded: Equatable {
        let path: String
        let contentType: String
        let thumbnail: String?
    }

    enum Failure: Error {
        case undecodable
    }

    private static let maxPixel: CGFloat = 1920
    private static let quality: CGFloat = 0.85

    /// The thumbnail travels ON THE WIRE inside the message, so it stays tiny.
    private static let thumbnailPixel: CGFloat = 64
    private static let thumbnailQuality: CGFloat = 0.5

    static func encode(_ data: Data, supportedTypes: [UTType]) throws -> Encoded {
        let thumbnail = ChatMediaImage
            .downsampled(data: data, maxPixel: thumbnailPixel)?
            .jpegData(compressionQuality: thumbnailQuality)?
            .base64EncodedString()

        // Forwarded untouched, like Android's `sendMediaFromUri` GIF branch: re-encoding a GIF
        // flattens it to a single still, so the peer would receive a frozen animation.
        if supportedTypes.contains(where: { $0.conforms(to: .gif) }) {
            return Encoded(
                path: try write(data, pathExtension: "gif"),
                contentType: ChatContentType.gif,
                thumbnail: thumbnail
            )
        }

        if supportedTypes.contains(where: { $0.conforms(to: .png) }) {
            return Encoded(
                path: try write(data, pathExtension: "png"),
                contentType: "image/png",
                thumbnail: thumbnail
            )
        }

        // Anything that is not PNG is re-encoded rather than forwarded: the library hands back
        // HEIC as readily as JPEG, and a peer told "image/jpeg" cannot decode HEIC bytes.
        guard let jpeg = ChatMediaImage
            .downsampled(data: data, maxPixel: maxPixel)?
            .jpegData(compressionQuality: quality)
        else {
            throw Failure.undecodable
        }

        return Encoded(
            path: try write(jpeg, pathExtension: "jpg"),
            contentType: ChatContentType.imageJPEG,
            thumbnail: thumbnail
        )
    }

    private static func write(_ data: Data, pathExtension: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zapp-media-\(UUID().uuidString).\(pathExtension)")

        try data.write(to: url, options: .atomic)

        return url.path
    }
}

// MARK: Placeholders

extension ChatRoom.State {
    static var initial: ChatRoom.State {
        .init(conversationId: "")
    }
}

extension ChatRoom {
    @MainActor
    static let initial = StoreOf<ChatRoom>(
        initialState: .initial
    ) {
        ChatRoom()
    }
}
