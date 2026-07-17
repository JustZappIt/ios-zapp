//
//  PushNotificationTestKey.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

extension PushNotificationClient: TestDependencyKey {
    static let testValue = PushNotificationClient(
        configure: { },
        didRegisterForRemoteNotifications: { _ in },
        didFailToRegisterForRemoteNotifications: { },
        latestState: { PushNotificationState() },
        stateStream: { Empty().eraseToAnyPublisher() },
        eventStream: { Empty().eraseToAnyPublisher() },
        setDeliveryEnabled: { _ in false },
        reconcile: { _, _ in },
        reassertSubscriptions: { },
        setActiveConversation: { _ in },
        setForeground: { _ in }
    )
}
