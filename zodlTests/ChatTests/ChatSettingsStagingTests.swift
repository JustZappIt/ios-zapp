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
    private struct Failure: Error { }

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
        #expect(store.state.chatSettingsSaveFailed)
        #expect(store.state.chatSettingsDraft.backgroundDelivery)
        #expect(store.state.canSaveChatSettings)

        await store.send(.chatSettingsAppeared)
        #expect(!store.state.chatSettingsDraft.backgroundDelivery)
    }

    @MainActor @Test func saveWaitsForEveryWriteAndPreservesFailedEditsForRetry() async {
        let receiptsStarted = AsyncStream<Void>.makeStream()
        let presenceStarted = AsyncStream<Void>.makeStream()
        let releaseReceipts = AsyncStream<Void>.makeStream()
        let releasePresence = AsyncStream<Void>.makeStream()
        let presenceFails = LockIsolated(true)
        let receiptWrites = LockIsolated<[Bool]>([])
        let presenceWrites = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.zappMessaging.setReadReceiptsEnabled = { value in
                receiptWrites.withValue { $0.append(value) }
                receiptsStarted.continuation.yield()
                for await _ in releaseReceipts.stream { break }
            }
            $0.zappMessaging.setPresenceVisible = { value in
                presenceWrites.withValue { $0.append(value) }
                presenceStarted.continuation.yield()
                for await _ in releasePresence.stream { break }
                if presenceFails.value { throw Failure() }
            }
        }
        store.exhaustivity = .off

        await store.send(.chatSettingsReadReceiptsToggled)
        await store.send(.chatSettingsOnlineStatusToggled)
        let draft = store.state.chatSettingsDraft
        await store.send(.chatSettingsSaveTapped)
        for await _ in receiptsStarted.stream { break }
        for await _ in presenceStarted.stream { break }

        #expect(store.state.pendingChatSettings == [.readReceipts, .onlineStatus])
        #expect(store.state.isChatSettingsBusy)
        #expect(!store.state.canSaveChatSettings)
        await store.send(.chatSettingsReadReceiptsToggled)
        await store.send(.chatSettingsAppeared)
        #expect(store.state.chatSettingsDraft == draft)

        releaseReceipts.continuation.finish()
        await store.receive(.readReceiptsFinished(false))
        #expect(store.state.pendingChatSettings == [.onlineStatus])
        #expect(store.state.isChatSettingsBusy)

        releasePresence.continuation.finish()
        await store.receive(.presenceFinished(true))
        #expect(!store.state.isChatSettingsBusy)
        #expect(store.state.chatSettingsSaveFailed)
        #expect(store.state.chatSettingsDraft == draft)
        #expect(!store.state.readReceiptsEnabled)
        #expect(store.state.presenceVisible)
        #expect(store.state.canSaveChatSettings)

        presenceFails.setValue(false)
        await store.send(.chatSettingsSaveTapped)
        await store.receive(.presenceFinished(false))
        await store.receive(.chatSettingsSaved)
        #expect(!store.state.chatSettingsSaveFailed)
        #expect(store.state.pendingChatSettings.isEmpty)
        #expect(store.state.chatSettingsDraft == store.state.chatSettingsInEffect)
        #expect(receiptWrites.value == [false])
        #expect(presenceWrites.value == [false, false])
        await store.finish()
    }

    @MainActor @Test func successfulSaveClosesOnlyTheChatSettingsDestination() {
        withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            var state = Root.State.initial
            state.path = .chatSettings
            let reducer = Root().coordinatorReduce()

            _ = reducer.reduce(into: &state, action: .chatProfile(.chatSettingsSaveTapped))
            #expect(state.path == .chatSettings)

            _ = reducer.reduce(into: &state, action: .chatProfile(.chatSettingsSaved))
            #expect(state.path == nil)

            state.path = .chatProfile
            _ = reducer.reduce(into: &state, action: .chatProfile(.chatSettingsSaved))
            #expect(state.path == .chatProfile)
        }
    }
}
