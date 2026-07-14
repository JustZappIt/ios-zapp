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
        var messagingState = ZappMessagingState()

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

        /// OUR connectivity, not the peer's — `isOnline` is this node's swarm
        /// state, the same field the list's connection chip reads. There is no
        /// per-peer presence on the client yet (the SDK emits
        /// `connection.peer_status`, but nothing surfaces it), so claiming
        /// "Online" under someone's name would be a fabrication: it would read as
        /// present whenever *we* have a network, even if they have been dark for
        /// weeks. Say nothing while healthy, and only own up when we are offline.
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
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case titleTapped
        case draftChanged(String)
        case sendTapped
        case messagesLoaded([ZMMessage])
        case messageReceived(ZMMessage)
        case messagingStateChanged(ZappMessagingState)
        case sendFailed(String)
        case replyTapped(ZMMessage)
        case cancelReplyTapped
        case pickedItemChanged(PhotosPickerItem?)
        case mediaSendFailed
        case messageStatusChanged(messageId: String, status: String)
        case mediaProgressChanged(mediaId: String, progress: Double)
        case mediaCompleted(mediaId: String, filePath: String)
    }

    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let conversationId = state.conversationId
                zappMessaging.setActiveConversation(conversationId)

                return .merge(
                    .run { _ in
                        try? await zappMessaging.markRead(conversationId)
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

            // Routed by Root into group info. Only a group has anything behind its
            // title; a DM's title is just the peer's name.
            case .titleTapped:
                return .none

            case .draftChanged(let draft):
                state.draft = draft
                state.sendDidFail = false
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
                state.replyingTo = nil
                state.pendingReply = replyTo
                let conversationId = state.conversationId

                return .run { send in
                    let message = try await zappMessaging.sendMessage(conversationId, content, reply)
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send message: \(error)")
                    await send(.sendFailed(content))
                }

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

            // Give the text back. The draft is cleared optimistically on send, so
            // without this a failed send destroys what the user typed, with no
            // bubble and no error — the message simply evaporates. The quote goes
            // back with it, or the retry silently drops the reply.
            case .sendFailed(let content):
                if state.draft.isEmpty {
                    state.draft = content
                }
                if state.replyingTo == nil {
                    state.replyingTo = state.pendingReply
                }
                state.pendingReply = nil
                state.sendDidFail = true
                return .none

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
