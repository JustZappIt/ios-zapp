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
        @Shared(.inMemory(.toast)) var toast: Toast.Edge? = nil

        var draftLinkPreview: ChatLinkPreview?
        var draftLinkPreviewURL: String?
        /// Dismissing a preview must stick for that URL: re-resolving it as the user keeps
        /// typing would put the card the user just closed straight back on screen.
        var dismissedLinkPreviewURLs: Set<String> = []
        var messageLinkPreviews: [String: ChatLinkPreview] = [:]
        var requestedLinkPreviewMessageIds: Set<String> = []

        /// Captured from the list before `setActiveConversation` clears the badge.
        /// Root creates a fresh room state for every entry, so the marker is shown
        /// once and naturally disappears after leaving and opening the room again.
        var unreadMessageCountAtEntry = 0

        /// Inbound events received after the room opened are already being read in
        /// place. Excluding them keeps the one-time separator pinned to the unread
        /// run that caused the user to open the room.
        var postEntryInboundMessageIds: Set<String> = []

        /// One read per visit, and only once history is on screen. Mirrors `ChatRoomReadGate`.
        var hasReadForVisit = false

        var replyingTo: ZMMessage?

        /// Held so a failed send can hand the quote back with the draft.
        var pendingReply: ZMMessage?

        /// Bound to the composer's `PhotosPicker`. Consumed and cleared the moment it lands.
        var pickedItem: PhotosPickerItem?

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

        /// The oldest of the most recent unread inbound messages currently loaded.
        /// If the unread run is larger than the page, the marker sits above the
        /// earliest loaded inbound message instead of disappearing.
        var unreadSeparatorMessageId: String? {
            guard unreadMessageCountAtEntry > 0 else { return nil }

            var remaining = unreadMessageCountAtEntry
            var boundaryId: String?

            for message in visibleMessages.reversed()
            where !message.isFromMe && !postEntryInboundMessageIds.contains(message.id) {
                boundaryId = message.id
                remaining -= 1

                if remaining == 0 {
                    break
                }
            }

            return boundaryId
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
        case draftLinkPreviewLoaded(url: String, preview: ChatLinkPreview?)
        case dismissDraftLinkPreviewTapped
        case messageAppeared(ZMMessage)
        case messageLinkPreviewLoaded(messageId: String, preview: ChatLinkPreview?)
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
        case copyMessageTapped(ZMMessage)
        case cancelReplyTapped
        case pickedItemChanged(PhotosPickerItem?)
        case mediaPasted(data: Data, type: UTType)
        case mediaSendFailed
        case mediaTooLarge
        case messageStatusChanged(messageId: String, status: String)
        case mediaProgressChanged(mediaId: String, progress: Double)
        case mediaCompleted(mediaId: String, filePath: String)
    }

    enum CancelID {
        case draftLinkPreview
    }

    @Dependency(\.chatLinkPreview) var chatLinkPreview
    @Dependency(\.continuousClock) var clock
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let conversationId = state.conversationId
                zappMessaging.setActiveConversation(conversationId)

                // Reading is deferred to `.messagesLoaded`: marking read on entry alone clears
                // the badge and emits receipts for messages that never reached the screen.
                return .merge(
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

            // Routed by Root into group info. Only a group has anything behind its
            // title; a DM's title is just the peer's name.
            case .titleTapped:
                return .none

            case .draftChanged(let draft):
                state.draft = draft
                state.sendDidFail = false
                state.sendFailureMessage = nil

                let url = ChatLinkPreviewParser.firstWebURL(in: draft)

                guard url != state.draftLinkPreviewURL else { return .none }

                state.draftLinkPreviewURL = url
                state.draftLinkPreview = nil

                guard let url, !state.dismissedLinkPreviewURLs.contains(url) else {
                    return .cancel(id: CancelID.draftLinkPreview)
                }

                // Debounced: a URL is typed one character at a time, and every prefix of it is
                // a syntactically valid host we would otherwise go and fetch.
                return .run { send in
                    try await clock.sleep(for: .milliseconds(600))
                    await send(.draftLinkPreviewLoaded(url: url, preview: chatLinkPreview.load(url)))
                }
                .cancellable(id: CancelID.draftLinkPreview, cancelInFlight: true)

            case .draftLinkPreviewLoaded(let url, let preview):
                guard url == state.draftLinkPreviewURL else { return .none }

                state.draftLinkPreview = preview
                return .none

            case .dismissDraftLinkPreviewTapped:
                if let url = state.draftLinkPreviewURL {
                    state.dismissedLinkPreviewURLs.insert(url)
                }

                state.draftLinkPreview = nil
                return .cancel(id: CancelID.draftLinkPreview)

            case .messageAppeared(let message):
                guard
                    !state.requestedLinkPreviewMessageIds.contains(message.id),
                    let url = ChatLinkPreviewParser.firstWebURL(in: message.content)
                else {
                    return .none
                }

                state.requestedLinkPreviewMessageIds.insert(message.id)

                let messageId = message.id
                return .run { send in
                    await send(.messageLinkPreviewLoaded(messageId: messageId, preview: chatLinkPreview.load(url)))
                }

            case .messageLinkPreviewLoaded(let messageId, let preview):
                guard let preview else { return .none }

                state.messageLinkPreviews[messageId] = preview
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
                        contentType: "text/plain",
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
                let visibleStatuses = state.messages.reduce(into: [String: String]()) { result, message in
                    guard let status = message.status else { return }
                    result[message.id] = ChatMessageStatusOrder.advance(
                        from: result[message.id],
                        to: status
                    )
                }
                state.messages = messages.map { message in
                    guard let visibleStatus = visibleStatuses[message.id] else { return message }

                    return message.withStatus(
                        ChatMessageStatusOrder.advance(from: message.status, to: visibleStatus)
                    )
                }
                .sorted { $0.timestamp < $1.timestamp }

                for index in state.messages.indices {
                    state.applyEarlyStatus(at: index)
                }

                guard !state.hasReadForVisit else { return .none }

                state.hasReadForVisit = true

                let conversationId = state.conversationId
                return .run { _ in
                    try await zappMessaging.markRead(conversationId)
                } catch: { error, _ in
                    LoggerProxy.error("Chat room mark-read failed: \(error)")
                }

            case .messageReceived(let message):
                guard !state.chatContacts.isBlocked(message.senderId) else { return .none }

                if message.isFromMe {
                    state.pendingReply = nil
                } else {
                    state.postEntryInboundMessageIds.insert(message.id)
                }

                state.insert(message)

                guard !message.isFromMe else { return .none }

                let conversationId = state.conversationId
                return .run { _ in
                    try await zappMessaging.markRead(conversationId)
                } catch: { error, _ in
                    LoggerProxy.error("Chat room mark-read for incoming message failed: \(error)")
                }

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

            case .copyMessageTapped(let message):
                pasteboard.setString(message.content.redacted)
                state.$toast.withLock { $0 = .top(String(localizable: .generalCopiedToTheClipboard)) }
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

                    if error as? ChatMediaEncoder.Failure == .tooLarge {
                        await send(.mediaTooLarge)
                    } else {
                        await send(.mediaSendFailed)
                    }
                }

            // The keyboard's GIF key and a pasted image arrive here rather than through the
            // picker, but ship down the same encoder — so a pasted GIF stays animated too.
            case .mediaPasted(let data, let type):
                state.sendDidFail = false
                let conversationId = state.conversationId

                return .run { send in
                    let encoded = try ChatMediaEncoder.encode(data, supportedTypes: [type])
                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        "",
                        encoded.thumbnail
                    )
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send pasted media: \(error)")

                    if error as? ChatMediaEncoder.Failure == .tooLarge {
                        await send(.mediaTooLarge)
                    } else {
                        await send(.mediaSendFailed)
                    }
                }

            case .mediaSendFailed:
                state.sendDidFail = true
                state.sendFailureMessage = nil
                return .none

            case .mediaTooLarge:
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomGifTooLarge)
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
            }
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

/// Delivery state only ever moves forward. Without this a late relay or persistence event can
/// overwrite recipient delivery/read confirmation and make the mark walk backwards.
enum ChatMessageStatusOrder {
    static func advance(from current: String?, to next: String) -> String {
        guard let nextStatus = ChatMessageStatusIndicator.Status.exact(wire: next) else {
            return current ?? next
        }
        guard let currentStatus = ChatMessageStatusIndicator.Status.exact(wire: current) else {
            return nextStatus.rawValue
        }

        if currentStatus == .read || currentStatus == .failed { return currentStatus.rawValue }
        if nextStatus == .failed || nextStatus == .read { return nextStatus.rawValue }
        if currentStatus == .delivered || nextStatus == .delivered { return Status.delivered.rawValue }
        if currentStatus == .sent || nextStatus == .sent { return Status.sent.rawValue }
        if currentStatus == .queued && nextStatus == .sending { return Status.queued.rawValue }

        return nextStatus.rawValue
    }

    private typealias Status = ChatMessageStatusIndicator.Status
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

    enum Failure: Error, Equatable {
        case undecodable
        case tooLarge
    }

    private static let maxPixel: CGFloat = 1920
    private static let quality: CGFloat = 0.85

    /// A GIF ships verbatim, so nothing downsizes it on the way out.
    static let maxGIFBytes = 8 * 1024 * 1024

    /// The thumbnail travels ON THE WIRE inside the message, so it stays tiny.
    private static let thumbnailPixel: CGFloat = 64
    private static let thumbnailQuality: CGFloat = 0.5

    static func encode(_ data: Data, supportedTypes: [UTType]) throws -> Encoded {
        let thumbnail = ChatMediaImage
            .downsampled(data: data, maxPixel: thumbnailPixel)?
            .jpegData(compressionQuality: thumbnailQuality)?
            .base64EncodedString()

        // Re-encoding a GIF collapses it to one frame. Sniffed from the bytes: PhotosUI
        // advertises a conforming still representation for an animated asset.
        if ChatMediaImage.isGIF(data) {
            guard data.count <= maxGIFBytes else { throw Failure.tooLarge }

            return Encoded(
                path: try write(data, pathExtension: "gif"),
                contentType: "image/gif",
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
            contentType: "image/jpeg",
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
