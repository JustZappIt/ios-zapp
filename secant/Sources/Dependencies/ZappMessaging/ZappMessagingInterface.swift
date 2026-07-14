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

    var isReady: Bool { phase == .ready }
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

    // MARK: Messages

    var messages: @Sendable (_ conversationId: String, _ limit: Int) async throws -> [ZMMessage] = { _, _ in [] }
    var sendMessage: @Sendable (_ conversationId: String, _ content: String) async throws -> ZMMessage
    var markRead: @Sendable (_ conversationId: String) async throws -> Void

    /// Fires for every inbound message, on every tab. Root subscribes so unread
    /// counts accrue while the user is elsewhere in the app.
    var messageReceivedStream: @Sendable () -> AnyPublisher<ZMMessage, Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// Tell the subsystem which room is on screen, so its inbound messages are
    /// not counted as unread.
    var setActiveConversation: @Sendable (String?) -> Void
}
