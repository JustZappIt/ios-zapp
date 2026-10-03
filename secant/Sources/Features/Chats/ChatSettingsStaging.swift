//
//  ChatSettingsStaging.swift
//  Zapp
//
//  Android's `ChatSettingsView` stages its three toggles and applies them together on Save,
//  which is enabled only while something differs from what is in effect. Saving hands each
//  changed value to the same per-setting paths the profile already runs, so the worklet calls,
//  the revert-on-failure and the notification permission prompt (which `setEnabled(true)`
//  raises) all stay where they were.
//

import ComposableArchitecture
import Foundation

/// The three values the Chat settings screen edits.
struct ChatSettingsValues: Equatable {
    var readReceipts = true
    var onlineStatus = true
    var backgroundDelivery = false
}

extension ChatProfile.State {
    /// What the switches are applying right now, as the profile tracks it.
    var chatSettingsInEffect: ChatSettingsValues {
        ChatSettingsValues(
            readReceipts: readReceiptsEnabled,
            onlineStatus: presenceVisible,
            backgroundDelivery: backgroundNotificationsEnabled
        )
    }

    var isChatSettingsBusy: Bool {
        isReadReceiptsBusy || isPresenceBusy || isBackgroundNotificationsBusy
    }

    var canSaveChatSettings: Bool {
        chatSettingsDraft != chatSettingsInEffect && !isChatSettingsBusy
    }
}

extension ChatProfile {
    func chatSettingsReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
                // Read afresh: the screen can open without the profile ever having appeared.
            case .chatSettingsAppeared:
                let latest = zappMessaging.latestState()
                if !state.isReadReceiptsBusy {
                    state.readReceiptsEnabled = latest.readReceiptsEnabled
                }
                if !state.isPresenceBusy {
                    state.presenceVisible = latest.presenceVisible
                }
                if !state.isBackgroundNotificationsBusy {
                    state.backgroundNotificationsEnabled = chatPushNotifications.isEnabled()
                }
                state.chatSettingsDraft = state.chatSettingsInEffect
                return .none

            case .chatSettingsReadReceiptsToggled:
                state.chatSettingsDraft.readReceipts.toggle()
                return .none

            case .chatSettingsOnlineStatusToggled:
                state.chatSettingsDraft.onlineStatus.toggle()
                return .none

            case .chatSettingsBackgroundDeliveryToggled:
                state.chatSettingsDraft.backgroundDelivery.toggle()
                return .none

            case .chatSettingsSaveTapped:
                guard state.canSaveChatSettings else { return .none }

                let draft = state.chatSettingsDraft
                let inEffect = state.chatSettingsInEffect
                var changes: [Effect<Action>] = []
                if draft.readReceipts != inEffect.readReceipts {
                    changes.append(.send(.readReceiptsToggled))
                }
                if draft.onlineStatus != inEffect.onlineStatus {
                    changes.append(.send(.presenceToggled))
                }
                if draft.backgroundDelivery != inEffect.backgroundDelivery {
                    changes.append(.send(.backgroundNotificationsToggled))
                }
                return .merge(changes)

            default:
                return .none
            }
        }
    }
}
