//
//  ChatPushNotifications.swift
//  Zapp
//

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
        clearTopics: { await ChatPushNotifications.shared.clearTopics() }
    )
}

extension ChatPushNotificationsClient: TestDependencyKey {
    static let testValue = ChatPushNotificationsClient(
        isEnabled: { false },
        setEnabled: { _ in false },
        sync: { _ in },
        clearTopics: { }
    )
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

        desiredTopics = Set(
            snapshot.conversations
                .filter { $0.lifecycle == "ready" }
                .flatMap(\.inboundTopics)
                .map(\.topic)
        )

        await reconcileTopics()
    }

    func clearTopics() async {
        desiredTopics.removeAll()
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
        // The notification is a generic doorbell. Foreground/cold-open
        // messaging reconciliation remains the authoritative message path.
    }
}
