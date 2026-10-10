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
        !pendingChatSettings.isEmpty || isReadReceiptsBusy || isPresenceBusy || isBackgroundNotificationsBusy
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
                guard !state.isChatSettingsBusy else { return .none }
                let latest = zappMessaging.latestState()
                state.readReceiptsEnabled = latest.readReceiptsEnabled
                state.presenceVisible = latest.presenceVisible
                state.backgroundNotificationsEnabled = chatPushNotifications.isEnabled()
                state.chatSettingsDraft = state.chatSettingsInEffect
                state.chatSettingsSaveFailed = false
                return .none

            case .chatSettingsReadReceiptsToggled:
                guard !state.isChatSettingsBusy else { return .none }
                state.chatSettingsDraft.readReceipts.toggle()
                state.chatSettingsSaveFailed = false
                return .none

            case .chatSettingsOnlineStatusToggled:
                guard !state.isChatSettingsBusy else { return .none }
                state.chatSettingsDraft.onlineStatus.toggle()
                state.chatSettingsSaveFailed = false
                return .none

            case .chatSettingsBackgroundDeliveryToggled:
                guard !state.isChatSettingsBusy else { return .none }
                state.chatSettingsDraft.backgroundDelivery.toggle()
                state.chatSettingsSaveFailed = false
                return .none

            case .chatSettingsSaveTapped:
                guard state.canSaveChatSettings else { return .none }

                let draft = state.chatSettingsDraft
                let inEffect = state.chatSettingsInEffect
                state.chatSettingsSaveFailed = false
                var changes: [Effect<Action>] = []
                if draft.readReceipts != inEffect.readReceipts {
                    state.pendingChatSettings.insert(.readReceipts)
                    changes.append(.send(.readReceiptsToggled))
                }
                if draft.onlineStatus != inEffect.onlineStatus {
                    state.pendingChatSettings.insert(.onlineStatus)
                    changes.append(.send(.presenceToggled))
                }
                if draft.backgroundDelivery != inEffect.backgroundDelivery {
                    state.pendingChatSettings.insert(.backgroundDelivery)
                    changes.append(.send(.backgroundNotificationsToggled))
                }
                return .merge(changes)

            case .readReceiptsFinished:
                return finishChatSetting(.readReceipts, state: &state)

            case .presenceFinished:
                return finishChatSetting(.onlineStatus, state: &state)

            case .backgroundNotificationsFinished:
                return finishChatSetting(.backgroundDelivery, state: &state)

            default:
                return .none
            }
        }
    }

    private func finishChatSetting(_ setting: ChatSetting, state: inout State) -> Effect<Action> {
        // The per-setting reducer runs first, so these are acknowledged values, including a
        // revert on failure or a refused notification permission. Track all requested writes
        // before starting any effect: an immediate completion must not dismiss a partial save.
        guard state.pendingChatSettings.remove(setting) != nil, state.pendingChatSettings.isEmpty else { return .none }

        state.chatSettingsSaveFailed = state.chatSettingsDraft != state.chatSettingsInEffect
        return state.chatSettingsSaveFailed ? .none : .send(.chatSettingsSaved)
    }
}
