//
//  PushNotificationInterface.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

extension DependencyValues {
    var pushNotifications: PushNotificationClient {
        get { self[PushNotificationClient.self] }
        set { self[PushNotificationClient.self] = newValue }
    }
}

enum PushAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional

    var allowsDelivery: Bool { self == .authorized || self == .provisional }
}

struct PushNotificationState: Equatable, Sendable {
    var isFirebaseAvailable = false
    var isDeliveryEnabled = false
    var authorizationStatus: PushAuthorizationStatus = .notDetermined
}

enum PushNotificationDestination: Equatable, Sendable {
    case chats
    case conversation(String)
}

enum PushNotificationEvent: Equatable, Sendable {
    case readinessChanged
    case authorizationChanged
    case tokenRefreshed
    case tapped(PushNotificationDestination)
}

struct PushTopicBinding: Codable, Equatable, Sendable {
    var topic: String
    var conversationId: String
    var writerPublicKey: String
}

struct PushTopicConversation: Equatable, Sendable {
    var conversationId: String
    var lifecycle: String
    var inboundTopics: [PushTopicBinding]
}

struct PushTopicSnapshot: Equatable, Sendable {
    var version: Int
    var hydrated: Bool
    var supportsGroups: Bool
    var conversations: [PushTopicConversation]
}

@DependencyClient
struct PushNotificationClient {
    var configure: @Sendable () -> Void
    var didRegisterForRemoteNotifications: @Sendable (Data) -> Void
    var didFailToRegisterForRemoteNotifications: @Sendable () -> Void

    var latestState: @Sendable () -> PushNotificationState = { PushNotificationState() }
    var stateStream: @Sendable () -> AnyPublisher<PushNotificationState, Never> = {
        Empty().eraseToAnyPublisher()
    }
    var eventStream: @Sendable () -> AnyPublisher<PushNotificationEvent, Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// The only permission entry point. Enabling requests alert/sound/badge
    /// authorization; disabling removes all opaque topic subscriptions.
    var setDeliveryEnabled: @Sendable (Bool) async -> Bool = { _ in false }

    /// A nil snapshot means the JS authority is not hydrated yet. Existing
    /// subscriptions are retained in that state.
    var reconcile: @Sendable (PushTopicSnapshot?, Set<String>) async -> Void
    var reassertSubscriptions: @Sendable () async -> Void

    var setActiveConversation: @Sendable (String?) -> Void
    var setForeground: @Sendable (Bool) -> Void
}
