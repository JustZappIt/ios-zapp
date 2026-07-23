//
//  ZappMessagingInterface.swift
//  Zapp
//

import Combine
import ComposableArchitecture
import Foundation
import ZappMessaging

extension DependencyValues {
    var zappMessaging: ZappMessagingClient {
        get { self[ZappMessagingClient.self] }
        set { self[ZappMessagingClient.self] = newValue }
    }
}

/// What the chat subsystem is doing, as the UI needs to see it.
///
/// Mirrors the flows `ChatBootstrap` exposes on Android (`isInitializing` /
/// `identity` / `isDeriving` / `chatIdentityErrorCode`), collapsed into one value
/// because TCA reducers want a single observable state rather than five streams.
struct ZappMessagingState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Worklet not started — no wallet yet.
        case idle
        /// Worklet booting.
        case initializing
        /// Worklet up, but no chat identity: the user has not chosen a name.
        case needsIdentity
        /// Deriving the identity from the wallet seed.
        case deriving
        /// Identity present. Chat works.
        case ready
        /// The worklet failed to boot. Distinct from a derive failure.
        case failed(String)
    }

    var phase: Phase = .idle
    var identity: ZMIdentity?

    /// Last *derive* failure, as a stable code for the setup screen's retry.
    /// A boot failure lives in `.phase` instead.
    var identityErrorCode: String?

    var isOnline = false
    var peerCount = 0

    /// "healthy" | "degraded" | "critical"
    var dhtHealth = "healthy"

    var totalUnreadCount = 0

    /// Latest operational failure, kept until a later successful operation clears it.
    /// Transport errors must remain inspectable instead of disappearing behind `try?`.
    var lastFailure: ZappMessagingFailure?

    /// Per-conversation unread. Counted app-side: the core never sends an
    /// `unreadCount` and `ZMConversation` carries no such field.
    var unreadCounts: [String: Int] = [:]

    /// Conversations with a peer currently online. Keyed by CONVERSATION id, not by
    /// peer key — the core truncates `peerId` to 12 chars, so it is not comparable
    /// to a public key and cannot identify who is online, only that someone is.
    var onlineConversationIds: Set<String> = []

    /// The worklet defaults read receipts ON at identity create/restore, before the
    /// app's preferences have loaded. The app re-asserts the user's real setting the
    /// moment identity lands, or a receipts-off user leaks receipts on every cold start.
    var readReceiptsEnabled = true
    var presenceVisible = true

    var isReady: Bool { phase == .ready }

    func unreadCount(for conversationId: String) -> Int {
        unreadCounts[conversationId] ?? 0
    }

    func isPeerOnline(in conversationId: String) -> Bool {
        onlineConversationIds.contains(conversationId)
    }
}

struct ZappMessagingFailure: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case advisory
        case error
    }

    let operation: ZappMessagingOperation
    let code: ZappMessagingFailureCode
    let message: String
    let severity: Severity
    let occurredAt: Date
}

enum ZappMessagingOperation: Equatable, Sendable {
    enum Local: String, Equatable, Sendable {
        case connectionDetails = "connection.details"
        case conversationRefresh = "conversation.refresh"
        case conversationCreate = "conversation.create"
        case conversationConnect = "conversation.connect"
        case messageList = "message.list"
        case messageSend = "message.send"
        case messageMarkRead = "message.mark_read"
        case mediaSend = "media.send"
        case setReadReceipts = "message.set_read_receipts"
        case setPresenceVisible = "message.set_presence_visible"
    }

    enum RecoveryArea: Equatable, Sendable {
        case connection
        case conversations
        case messages
        case privacy
    }

    case local(Local)
    case sdk(ZMOperationalFailure.Operation)

    var identifier: String {
        switch self {
        case .local(let operation): return operation.rawValue
        case .sdk(let operation): return operation.identifier
        }
    }

    var recoveryArea: RecoveryArea {
        switch self {
        case .local(.connectionDetails): return .connection
        case .local(.conversationRefresh), .local(.conversationCreate), .local(.conversationConnect): return .conversations
        case .local(.messageList), .local(.messageSend), .local(.messageMarkRead), .local(.mediaSend): return .messages
        case .local(.setReadReceipts), .local(.setPresenceVisible): return .privacy
        case .sdk(.connectionResume), .sdk(.pushNotification), .sdk(.ipcEvent), .sdk(.workletRecovery):
            return .connection
        case .sdk(.conversationConnect), .sdk(.conversationRefresh): return .conversations
        case .sdk(.messagePersist): return .messages
        }
    }

    func recovers(_ failedOperation: ZappMessagingOperation) -> Bool {
        if self == failedOperation { return true }

        switch self {
        case .local(.connectionDetails), .local(.conversationRefresh), .local(.messageList):
            return recoveryArea == failedOperation.recoveryArea
        case .local(.setReadReceipts), .local(.setPresenceVisible):
            return failedOperation.recoveryArea == .privacy
        default:
            return false
        }
    }
}

enum ZappMessagingFailureCode: Equatable, Sendable {
    case ownPublicKey
    case sdkNotReady
    case ipcTimeout
    case ipc(ZMErrorCode)
    case workletError
    case badResponse
    case invalidSeed
    case noIdentity
    case operational(ZMOperationalFailure.Code)
    case unknown(String)

    init(error: Error) {
        if error is ZappMessagingAppError {
            self = .ownPublicKey
            return
        }
        guard let zmError = error as? ZMError else {
            self = .unknown((error as NSError).domain)
            return
        }

        switch zmError {
        case .notInitialized: self = .sdkNotReady
        case .ipcTimeout: self = .ipcTimeout
        case .ipcError(let code, _): self = .ipc(code)
        case .workletError: self = .workletError
        case .invalidData: self = .badResponse
        case .invalidSeedPhrase: self = .invalidSeed
        case .identityNotFound: self = .noIdentity
        default: self = .unknown("UNKNOWN")
        }
    }

    var identifier: String {
        switch self {
        case .ownPublicKey: return "OWN_PUBLIC_KEY"
        case .sdkNotReady: return "SDK_NOT_READY"
        case .ipcTimeout: return "IPC_TIMEOUT"
        case .ipc(let code): return code.rawValue
        case .workletError: return "WORKLET_ERROR"
        case .badResponse: return "BAD_RESPONSE"
        case .invalidSeed: return "INVALID_SEED"
        case .noIdentity: return "NO_IDENTITY"
        case .operational(let code): return code.identifier
        case .unknown(let value): return value
        }
    }
}

enum ZappMessagingAppError: LocalizedError, Equatable, Sendable {
    case ownPublicKey

    var errorDescription: String? {
        switch self {
        case .ownPublicKey:
            return String(localizable: .chatRoomOwnKeySendFailed)
        }
    }
}

@DependencyClient
struct ZappMessagingClient {
    // MARK: Lifecycle

    /// Boot the worklet. Idempotent. Reads the wallet seed itself, so it must not
    /// be called before the wallet exists — Root calls it from
    /// `.initializationSuccessfullyDone`.
    var start: @Sendable () -> Void

    /// Park the worklet on background. iOS suspends the process anyway; a
    /// graceful park beats being frozen mid-socket.
    var suspend: @Sendable () -> Void
    var resume: @Sendable () -> Void

    /// Stop the worklet and delete its data dir. For wallet reset.
    var wipe: @Sendable () async -> Void

    // MARK: Identity

    /// Queue the display name and derive the chat identity from the wallet seed.
    /// The name is the sole trigger for derivation — nothing happens without it.
    var setDisplayName: @Sendable (String) -> Void

    /// Re-attempt a failed derive. No-ops while one is in flight.
    var retryIdentityDerivation: @Sendable () -> Void

    var updateDisplayName: @Sendable (String) async throws -> Void

    // MARK: State

    var stateStream: @Sendable () -> AnyPublisher<ZappMessagingState, Never> = {
        Empty().eraseToAnyPublisher()
    }
    var latestState: @Sendable () -> ZappMessagingState = { ZappMessagingState() }

    // MARK: Conversations

    var conversationsStream: @Sendable () -> AnyPublisher<[ZMConversation], Never> = {
        Empty().eraseToAnyPublisher()
    }
    var refreshConversations: @Sendable () async throws -> Void

    /// Full live transport diagnostics used by the network status sheet.
    var connectionDetails: @Sendable () async throws -> ZMConnectionDetails

    /// Start (or re-open) a direct conversation with a peer's Ed25519 public key.
    /// Returns the existing conversation if one already exists for that peer.
    var createDirectConversation: @Sendable (
        _ publicKey: String,
        _ displayName: String?
    ) async throws -> ZMConversation

    // MARK: Groups

    var createGroup: @Sendable (
        _ name: String,
        _ participantKeys: [String]
    ) async throws -> ZMConversation

    var renameGroup: @Sendable (_ conversationId: String, _ name: String) async throws -> Void
    var addMember: @Sendable (_ conversationId: String, _ publicKey: String, _ displayName: String?) async throws -> Void
    var leaveConversation: @Sendable (_ conversationId: String) async throws -> Void
    var removeConversation: @Sendable (_ conversationId: String) async throws -> Void

    /// Whether the deterministic direct conversation with this peer was explicitly removed on
    /// this device, so a rejoin can confirm before recreating a tombstoned DM. Defaults to false
    /// so previews and un-customized mocks skip the prompt.
    var hasLeftDirectConversation: @Sendable (_ publicKey: String) async throws -> Bool = { _ in false }

    // MARK: Messages

    var messages: @Sendable (_ conversationId: String, _ limit: Int) async throws -> [ZMMessage] = { _, _ in [] }

    var sendMessage: @Sendable (
        _ conversationId: String,
        _ content: String,
        _ replyTo: ZMReplyContext?
    ) async throws -> ZMMessage

    var sendMedia: @Sendable (
        _ conversationId: String,
        _ mediaPath: String,
        _ contentType: String,
        _ caption: String,
        _ thumbnailData: String?
    ) async throws -> ZMMessage

    var markRead: @Sendable (_ conversationId: String) async throws -> Void

    /// Delivery-state changes for messages already on screen (queued -> sent -> read).
    var messageStatusStream: @Sendable () -> AnyPublisher<(messageId: String, conversationId: String, status: String), Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// (mediaId, 0...1). Fires for both directions.
    var mediaProgressStream: @Sendable () -> AnyPublisher<(mediaId: String, progress: Double), Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// (mediaId, localPath) — an inbound transfer landed on disk.
    var mediaCompleteStream: @Sendable () -> AnyPublisher<(mediaId: String, filePath: String), Never> = {
        Empty().eraseToAnyPublisher()
    }

    // MARK: Privacy toggles

    var setReadReceiptsEnabled: @Sendable (Bool) async throws -> Void
    var setPresenceVisible: @Sendable (Bool) async throws -> Void

    /// Fires for every inbound message, on every tab. Root subscribes so unread
    /// counts accrue while the user is elsewhere in the app.
    var messageReceivedStream: @Sendable () -> AnyPublisher<ZMMessage, Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// Tell the subsystem which room is on screen, so its inbound messages are
    /// not counted as unread.
    var setActiveConversation: @Sendable (String?) -> Void

    /// Blocked senders must not bump the unread badge. Unread is counted inside the
    /// messaging subsystem, which cannot see the contact list, so Root pushes the
    /// set down whenever it changes.
    var setBlockedKeys: @Sendable (Set<String>) -> Void
}
