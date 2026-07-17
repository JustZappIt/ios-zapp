//
//  PushNotificationLiveKey.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import FirebaseCore
@preconcurrency import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

extension PushNotificationClient: DependencyKey {
    static let liveValue: PushNotificationClient = Self.live()

    static func live() -> Self {
        let manager = FirebasePushNotificationManager.shared
        return PushNotificationClient(
            configure: { manager.configure() },
            didRegisterForRemoteNotifications: { manager.didRegisterForRemoteNotifications(deviceToken: $0) },
            didFailToRegisterForRemoteNotifications: { manager.didFailToRegisterForRemoteNotifications() },
            latestState: { manager.latestState },
            stateStream: { manager.stateSubject.eraseToAnyPublisher() },
            eventStream: { manager.eventSubject.eraseToAnyPublisher() },
            setDeliveryEnabled: { await manager.setDeliveryEnabled($0) },
            reconcile: { await manager.reconcile(snapshot: $0, blockedWriters: $1) },
            reassertSubscriptions: { await manager.reassertSubscriptions() },
            setActiveConversation: { manager.setActiveConversation($0) },
            setForeground: { manager.setForeground($0) }
        )
    }
}

enum FirebaseConfigurationLoader {
    static func load(path: String?, expectedBundleId: String?) -> FirebaseOptions? {
        guard let path,
              let expectedBundleId,
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == expectedBundleId,
              options.projectID == expectedProjectId,
              !options.gcmSenderID.isEmpty else {
            return nil
        }
        return options
    }

    private static let expectedProjectId = "zapp-b3154"
}

private final class FirebaseTopicSubscriptionClient: PushTopicSubscriptionClient, @unchecked Sendable {
    func subscribe(to topic: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard FirebaseApp.app() != nil else {
                continuation.resume(throwing: PushUnavailableError())
                return
            }
            Messaging.messaging().subscribe(toTopic: topic) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func unsubscribe(from topic: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard FirebaseApp.app() != nil else {
                continuation.resume(throwing: PushUnavailableError())
                return
            }
            Messaging.messaging().unsubscribe(fromTopic: topic) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private struct PushUnavailableError: Error { }

private final class FirebasePushNotificationManager: NSObject, @unchecked Sendable {
    static let shared = FirebasePushNotificationManager()

    let stateSubject: CurrentValueSubject<PushNotificationState, Never>
    let eventSubject = PassthroughSubject<PushNotificationEvent, Never>()

    var latestState: PushNotificationState { stateLock.withLock { stateSubject.value } }

    private let notificationCenter = UNUserNotificationCenter.current()
    private let store = UserDefaultsPushTopicStore()
    private let reconciler: PushTopicReconciler
    private let stateLock = NSLock()
    private let contextLock = NSLock()

    private var expectedSenderId: String?
    private var blockedWriters: Set<String> = []
    private var activeConversationId: String?
    private var isForeground = true
    private var didConfigure = false

    private override init() {
        let initial = store.loadSynchronously()
        stateSubject = CurrentValueSubject(
            PushNotificationState(isDeliveryEnabled: initial.deliveryEnabled)
        )
        reconciler = PushTopicReconciler(
            client: FirebaseTopicSubscriptionClient(),
            store: store,
            onFailure: { LoggerProxy.event("Push notification topic operation failed") }
        )
        super.init()
    }

    func configure() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !didConfigure else { return }
        didConfigure = true
        notificationCenter.delegate = self

        let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
        guard let options = FirebaseConfigurationLoader.load(
            path: path,
            expectedBundleId: Bundle.main.bundleIdentifier
        ) else {
            mutateState {
                $0.isFirebaseAvailable = false
                $0.isDeliveryEnabled = false
            }
            Task { await reconciler.reconcile(desired: [:], enabled: false) }
            LoggerProxy.event("Firebase configuration unavailable; chat push disabled")
            eventSubject.send(.readinessChanged)
            return
        }

        FirebaseApp.configure(options: options)
        expectedSenderId = options.gcmSenderID
        Messaging.messaging().delegate = self
        Messaging.messaging().isAutoInitEnabled = latestState.isDeliveryEnabled
        mutateState { $0.isFirebaseAvailable = true }

        Task { [weak self] in
            guard let self else { return }
            let settings = await notificationCenter.notificationSettings()
            let authorization = Self.authorizationStatus(settings.authorizationStatus)
            mutateState {
                $0.authorizationStatus = authorization
                if !authorization.allowsDelivery { $0.isDeliveryEnabled = false }
            }

            if authorization.allowsDelivery && latestState.isDeliveryEnabled {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            } else if !authorization.allowsDelivery {
                await reconciler.reconcile(desired: [:], enabled: false)
            }
            eventSubject.send(.readinessChanged)
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard latestState.isFirebaseAvailable else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    func didFailToRegisterForRemoteNotifications() {
        LoggerProxy.event("APNs registration failed")
    }

    func setDeliveryEnabled(_ enabled: Bool) async -> Bool {
        if !enabled {
            await reconciler.reconcile(desired: [:], enabled: false)
            if FirebaseApp.app() != nil {
                await MainActor.run { Messaging.messaging().isAutoInitEnabled = false }
            }
            mutateState { $0.isDeliveryEnabled = false }
            eventSubject.send(.authorizationChanged)
            return true
        }

        guard latestState.isFirebaseAvailable else { return false }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await notificationCenter.notificationSettings()
            let authorization = Self.authorizationStatus(settings.authorizationStatus)
            let allowed = granted && authorization.allowsDelivery

            mutateState {
                $0.authorizationStatus = authorization
                $0.isDeliveryEnabled = allowed
            }

            guard allowed else {
                await reconciler.reconcile(desired: [:], enabled: false)
                eventSubject.send(.authorizationChanged)
                return false
            }

            await reconciler.reconcile(desired: nil, enabled: true)
            await MainActor.run {
                Messaging.messaging().isAutoInitEnabled = true
                UIApplication.shared.registerForRemoteNotifications()
            }
            eventSubject.send(.authorizationChanged)
            return true
        } catch {
            mutateState {
                $0.authorizationStatus = .denied
                $0.isDeliveryEnabled = false
            }
            await reconciler.reconcile(desired: [:], enabled: false)
            eventSubject.send(.authorizationChanged)
            return false
        }
    }

    func reconcile(snapshot: PushTopicSnapshot?, blockedWriters: Set<String>) async {
        contextLock.withLock { self.blockedWriters = blockedWriters }
        let state = latestState

        guard state.isDeliveryEnabled else {
            await reconciler.reconcile(desired: [:], enabled: false)
            return
        }
        guard state.isFirebaseAvailable, state.authorizationStatus.allowsDelivery else { return }
        guard let snapshot, snapshot.hydrated else {
            await reconciler.reconcile(desired: nil, enabled: true)
            return
        }

        let desired = PushTopicDesiredBindings.make(
            snapshot: snapshot,
            blockedWriters: blockedWriters
        )

        await reconciler.reconcile(desired: desired, enabled: true)
    }

    func reassertSubscriptions() async {
        await reconciler.forceResubscribe()
    }

    func setActiveConversation(_ conversationId: String?) {
        contextLock.withLock { activeConversationId = conversationId }
    }

    func setForeground(_ foreground: Bool) {
        contextLock.withLock { isForeground = foreground }
        guard foreground else { return }
        Task { [weak self] in await self?.refreshAuthorization() }
    }

    private func refreshAuthorization() async {
        guard latestState.isFirebaseAvailable, FirebaseApp.app() != nil else { return }
        let settings = await notificationCenter.notificationSettings()
        let authorization = Self.authorizationStatus(settings.authorizationStatus)
        let previous = latestState

        mutateState {
            $0.authorizationStatus = authorization
            if !authorization.allowsDelivery { $0.isDeliveryEnabled = false }
        }

        if !authorization.allowsDelivery && previous.isDeliveryEnabled {
            await reconciler.reconcile(desired: [:], enabled: false)
            await MainActor.run { Messaging.messaging().isAutoInitEnabled = false }
        } else if authorization.allowsDelivery && latestState.isDeliveryEnabled {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }

        if previous.authorizationStatus != authorization || previous.isDeliveryEnabled != latestState.isDeliveryEnabled {
            eventSubject.send(.authorizationChanged)
        }
    }

    private func mutateState(_ change: (inout PushNotificationState) -> Void) {
        stateLock.withLock {
            var state = stateSubject.value
            change(&state)
            if state != stateSubject.value { stateSubject.send(state) }
        }
    }

    private static func authorizationStatus(_ status: UNAuthorizationStatus) -> PushAuthorizationStatus {
        switch status {
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

}

extension FirebasePushNotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard fcmToken != nil else { return }
        Task {
            await reconciler.forceResubscribe()
            eventSubject.send(.tokenRefreshed)
        }
    }
}

extension FirebasePushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard let doorbell = ChatDoorbellValidator.validate(
            userInfo: notification.request.content.userInfo,
            expectedSenderId: expectedSenderId
        ) else {
            return []
        }

        let binding = store.binding(for: doorbell.topic)
        let context = contextLock.withLock {
            (blockedWriters, activeConversationId, isForeground)
        }
        let shouldPresent = ChatDoorbellDecider.shouldPresent(
            binding: binding,
            blockedWriters: context.0,
            activeConversationId: context.1,
            isForeground: context.2,
            deliveryEnabled: latestState.isDeliveryEnabled
        )
        return shouldPresent ? [.banner, .sound] : []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let doorbell = ChatDoorbellValidator.validate(
            userInfo: response.notification.request.content.userInfo,
            expectedSenderId: expectedSenderId
        ) else {
            return
        }

        let binding = store.binding(for: doorbell.topic)
        let blocked = contextLock.withLock { blockedWriters }
        eventSubject.send(.tapped(ChatDoorbellDecider.destination(binding: binding, blockedWriters: blocked)))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
