//
//  NotificationDelegateDispatcher.swift
//  Zapp
//
//  `UNUserNotificationCenter.delegate` is a single slot and Zapp has two consumers: upstream's
//  migration notifications and our fork-only chat push. Whoever assigned last used to win, killing
//  the other's taps with no compiler error. This routes each notification to its owner instead.
//

import Foundation
import UserNotifications

// `@MainActor` to match `ChatPushNotifications`, whose `topic(from:)` and delegate methods are
// main-actor isolated.
@MainActor
final class NotificationDelegateDispatcher: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let migration: MigrationNotificationCenterDelegate
    private let chat: ChatPushNotifications

    init(migration: MigrationNotificationCenterDelegate, chat: ChatPushNotifications) {
        self.migration = migration
        self.chat = chat
    }

    private func isMigration(_ request: UNNotificationRequest) -> Bool {
        request.identifier.hasPrefix(MigrationNotification.identifierPrefix)
    }

    private func isChat(_ request: UNNotificationRequest) -> Bool {
        ChatPushNotifications.topic(from: request.content.userInfo) != nil
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        if isMigration(request) {
            migration.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        } else if isChat(request) {
            Task {
                await chat.userNotificationCenter(center, didReceive: response)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let request = notification.request
        if isMigration(request) {
            // Migration's own policy presents nothing while foregrounded and still drives the tick
            // belt, so it must be asked rather than unioned with chat's options.
            migration.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else if isChat(request) {
            Task {
                let options = await chat.userNotificationCenter(center, willPresent: notification)
                completionHandler(options)
            }
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }
}
