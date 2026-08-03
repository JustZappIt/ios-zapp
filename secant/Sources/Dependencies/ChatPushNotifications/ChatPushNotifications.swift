//
//  ChatPushNotifications.swift
//  Zapp
//

import Combine
import ComposableArchitecture
import FirebaseCore
@preconcurrency import FirebaseMessaging
import Foundation
import UIKit
@preconcurrency import UserNotifications
import ZappMessaging

@DependencyClient
struct ChatPushNotificationsClient {
    var isEnabled: @Sendable () -> Bool = { false }
    var setEnabled: @Sendable (_ enabled: Bool) async -> Bool = { _ in false }
    var sync: @Sendable (_ snapshot: ZMPushTopicSnapshot) async -> Void
    var clearTopics: @Sendable () async -> Void

    /// Emits the conversation a tapped notification belongs to. Resolved on device from the
    /// FCM topic, which the app already maps to a conversation to subscribe in the first place.
    var conversationTapStream: @Sendable () -> AnyPublisher<String, Never> = {
        Empty().eraseToAnyPublisher()
    }
}

extension DependencyValues {
    var chatPushNotifications: ChatPushNotificationsClient {
        get { self[ChatPushNotificationsClient.self] }
        set { self[ChatPushNotificationsClient.self] = newValue }
    }
}

extension ChatPushNotificationsClient: DependencyKey {
    static let liveValue = ChatPushNotificationsClient(
        isEnabled: {
            UserDefaults.standard.bool(forKey: "zappChat.backgroundNotificationsEnabled")
        },
        setEnabled: { await ChatPushNotifications.shared.setEnabled($0) },
        sync: { await ChatPushNotifications.shared.sync($0) },
        clearTopics: { await ChatPushNotifications.shared.clearTopics() },
        conversationTapStream: { ChatNotificationTapRelay.shared.stream }
    )
}

extension ChatPushNotificationsClient: TestDependencyKey {
    static let testValue = ChatPushNotificationsClient(
        isEnabled: { false },
        setEnabled: { _ in false },
        sync: { _ in },
        clearTopics: { },
        conversationTapStream: { Empty().eraseToAnyPublisher() }
    )
}

/// Sits outside the main actor so the dependency's synchronous stream accessor can reach it.
final class ChatNotificationTapRelay: @unchecked Sendable {
    static let shared = ChatNotificationTapRelay()

    private let subject = PassthroughSubject<String, Never>()

    var stream: AnyPublisher<String, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ conversationId: String) {
        subject.send(conversationId)
    }
}

@MainActor
final class ChatPushNotifications: NSObject {
    static let shared = ChatPushNotifications()

    private enum PreferenceKey {
        static let enabled = "zappChat.backgroundNotificationsEnabled"
        static let subscribedTopics = "zappChat.subscribedPushTopics"
    }

    private let defaults = UserDefaults.standard
    private var configured = false
    private var desiredTopics = Set<String>()

    /// Topic -> conversation, kept from the same snapshot that drives subscription. The relay
    /// never learns which conversation a notification is for; the mapping only exists here.
    private var topicConversations: [String: String] = [:]

    var isEnabled: Bool {
        defaults.bool(forKey: PreferenceKey.enabled)
    }

    func configure(application: UIApplication) {
        guard !configured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            LoggerProxy.event("Chat push disabled: no matching Firebase configuration")
            return
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        configured = true
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        Messaging.messaging().isAutoInitEnabled = isEnabled

        if isEnabled {
            application.registerForRemoteNotifications()
        }
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        guard configured else {
            LoggerProxy.event("Chat push unavailable: Firebase is not configured for this target")
            return false
        }

        if enabled {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    defaults.set(false, forKey: PreferenceKey.enabled)
                    return false
                }

                defaults.set(true, forKey: PreferenceKey.enabled)
                Messaging.messaging().isAutoInitEnabled = true
                UIApplication.shared.registerForRemoteNotifications()
                await reconcileTopics()
                return true
            } catch {
                LoggerProxy.error("Chat notification permission failed: \(error.localizedDescription)")
                defaults.set(false, forKey: PreferenceKey.enabled)
                return false
            }
        }

        defaults.set(false, forKey: PreferenceKey.enabled)
        Messaging.messaging().isAutoInitEnabled = false
        UIApplication.shared.unregisterForRemoteNotifications()
        await clearTopics()
        return false
    }

    func sync(_ snapshot: ZMPushTopicSnapshot) async {
        guard configured, isEnabled, snapshot.hydrated else { return }

        let ready = snapshot.conversations.filter { $0.lifecycle == "ready" }

        desiredTopics = Set(ready.flatMap(\.inboundTopics).map(\.topic))
        topicConversations = ready.reduce(into: [:]) { result, conversation in
            for inbound in conversation.inboundTopics {
                result[inbound.topic] = conversation.conversationId
            }
        }

        await reconcileTopics()
    }

    func clearTopics() async {
        desiredTopics.removeAll()
        topicConversations.removeAll()
        let previous = subscribedTopics

        // Publish the empty routing set before remote removal. A delayed
        // notification can no longer be treated as locally subscribed.
        defaults.removeObject(forKey: PreferenceKey.subscribedTopics)

        guard configured else { return }
        for topic in previous {
            do {
                try await Messaging.messaging().unsubscribe(fromTopic: topic)
            } catch {
                LoggerProxy.error("Chat push topic removal failed")
            }
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard configured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        LoggerProxy.error("APNs registration failed: \(error.localizedDescription)")
    }

    private var subscribedTopics: Set<String> {
        Set(defaults.stringArray(forKey: PreferenceKey.subscribedTopics) ?? [])
    }

    private func reconcileTopics() async {
        guard configured, isEnabled, Messaging.messaging().fcmToken != nil else { return }

        let previous = subscribedTopics
        let removed = previous.subtracting(desiredTopics)
        let added = desiredTopics.subtracting(previous)

        // Remove local routing before asking FCM to unsubscribe.
        var published = previous.subtracting(removed)
        defaults.set(Array(published).sorted(), forKey: PreferenceKey.subscribedTopics)

        for topic in removed {
            do {
                try await Messaging.messaging().unsubscribe(fromTopic: topic)
            } catch {
                LoggerProxy.error("Chat push topic removal failed")
            }
        }

        for topic in added {
            do {
                try await Messaging.messaging().subscribe(toTopic: topic)
                published.insert(topic)
                defaults.set(Array(published).sorted(), forKey: PreferenceKey.subscribedTopics)
            } catch {
                LoggerProxy.error("Chat push topic subscription failed")
            }
        }
    }
}

extension ChatPushNotifications: @preconcurrency MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard fcmToken != nil else { return }
        Task { @MainActor [weak self] in
            await self?.reconcileTopics()
        }
    }
}

extension ChatPushNotifications: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // The notification stays a generic doorbell: reconciliation remains the authoritative
        // message path. The topic is the only routing hint it carries, and it is resolved here.
        guard
            let topic = Self.topic(from: response.notification.request.content.userInfo),
            let conversationId = topicConversations[topic]
        else {
            return
        }

        ChatNotificationTapRelay.shared.send(conversationId)
    }

    /// FCM delivers topic sends as `/topics/<topic>` in `from`.
    static func topic(from userInfo: [AnyHashable: Any]) -> String? {
        guard let from = userInfo["from"] as? String, from.hasPrefix("/topics/") else { return nil }

        let topic = String(from.dropFirst("/topics/".count))

        return topic.isEmpty ? nil : topic
    }
}
