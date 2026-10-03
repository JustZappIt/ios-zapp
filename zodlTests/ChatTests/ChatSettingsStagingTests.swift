//
//  ChatSettingsStagingTests.swift
//  zodlTests
//
//  Android's Chat settings stage their toggles behind Save: nothing reaches the worklet or the
//  notification permission prompt until Save, and only the values that changed are applied.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite(.serialized) struct ChatSettingsStagingTests {
    @MainActor @Test func togglesAreStagedUntilSave() async {
        let readReceiptWrites = LockIsolated<[Bool]>([])
        let pushRequests = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.zappMessaging.latestState = {
                var state = ZappMessagingState()
                state.readReceiptsEnabled = true
                return state
            }
            $0.zappMessaging.setReadReceiptsEnabled = { value in readReceiptWrites.withValue { $0.append(value) } }
            $0.zappMessaging.syncPushNotifications = { }
            $0.chatPushNotifications.isEnabled = { false }
            $0.chatPushNotifications.setEnabled = { enabled in
                pushRequests.withValue { $0.append(enabled) }
                return enabled
            }
        }
        store.exhaustivity = .off

        await store.send(.chatSettingsAppeared)
        #expect(!store.state.canSaveChatSettings)

        await store.send(.chatSettingsReadReceiptsToggled)
        await store.send(.chatSettingsBackgroundDeliveryToggled)
        #expect(store.state.canSaveChatSettings)
        #expect(readReceiptWrites.value.isEmpty)
        #expect(pushRequests.value.isEmpty)

        // Toggling back to what is in effect leaves nothing to save.
        await store.send(.chatSettingsReadReceiptsToggled)
        await store.send(.chatSettingsReadReceiptsToggled)

        await store.send(.chatSettingsSaveTapped)
        await store.finish()
        await store.skipReceivedActions()

        // The online-status switch was never touched, so it is never written.
        #expect(readReceiptWrites.value == [false])
        #expect(pushRequests.value == [true])
        #expect(!store.state.readReceiptsEnabled)
        #expect(store.state.backgroundNotificationsEnabled)
        #expect(!store.state.canSaveChatSettings)
    }

    /// A refused notification permission leaves delivery off, and the draft no longer differs
    /// once the screen re-reads what is in effect.
    @MainActor @Test func aRefusedPermissionLeavesDeliveryOff() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.zappMessaging.latestState = { ZappMessagingState() }
            $0.chatPushNotifications.isEnabled = { false }
            $0.chatPushNotifications.setEnabled = { _ in false }
        }
        store.exhaustivity = .off

        await store.send(.chatSettingsAppeared)
        await store.send(.chatSettingsBackgroundDeliveryToggled)
        await store.send(.chatSettingsSaveTapped)
        await store.finish()
        await store.skipReceivedActions()

        #expect(!store.state.backgroundNotificationsEnabled)

        await store.send(.chatSettingsAppeared)
        #expect(!store.state.chatSettingsDraft.backgroundDelivery)
    }
}
