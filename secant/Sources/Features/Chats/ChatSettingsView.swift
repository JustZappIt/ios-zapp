//
//  ChatSettingsView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The three chat preferences on one screen, as Android's `ChatSettingsView` gathers them: the
/// toggles are staged and applied together by Save in the bottom bar, which is enabled only while
/// something has changed. Back discards the draft.
struct ChatSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatProfile>
    let onBack: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .chatSettingsTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        ZappSettingsGroup(
                            title: String(localizable: .settingsYouGroupPrivacy),
                            footer: String(localizable: .chatSettingsPrivacyFooter)
                        ) {
                            ZappToggleRow(
                                title: String(localizable: .chatPrivacyReadReceiptsToggleTitle),
                                subtitle: String(localizable: .chatPrivacyReadReceiptsToggleSubtitle),
                                icon: Asset.Assets.Icons.checkSolid.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.chatSettingsDraft.readReceipts,
                                isEnabled: !store.isChatSettingsBusy
                            ) {
                                store.send(.chatSettingsReadReceiptsToggled)
                            }

                            ZappRowDivider(inset: true)

                            ZappToggleRow(
                                title: String(localizable: .chatPrivacyOnlineStatusToggleTitle),
                                subtitle: String(localizable: .chatPrivacyOnlineStatusToggleSubtitle),
                                icon: Asset.Assets.Icons.user.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.chatSettingsDraft.onlineStatus,
                                isEnabled: !store.isChatSettingsBusy
                            ) {
                                store.send(.chatSettingsOnlineStatusToggled)
                            }
                        }

                        ZappSettingsGroup(
                            title: String(localizable: .chatSettingsSectionDelivery),
                            footer: String(localizable: .chatSettingsDeliveryFooter)
                        ) {
                            ZappToggleRow(
                                title: String(localizable: .chatNotificationsBackgroundTitle),
                                subtitle: String(localizable: .chatNotificationsBackgroundSubtitle),
                                icon: Asset.Assets.Icons.messageChat.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.chatSettingsDraft.backgroundDelivery,
                                isEnabled: !store.isChatSettingsBusy
                            ) {
                                store.send(.chatSettingsBackgroundDeliveryToggled)
                            }
                        }

                        if store.chatSettingsSaveFailed {
                            Text(String(localizable: .chatProfileSaveFailed))
                                .zappFont(.caption, style: ZappColors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(Design.Spacing._lg)
                        }
                    }
                    .padding(.vertical, Design.Spacing._xl)
                }

                ZappBottomActionBar(onBack: onBack, isBackEnabled: !store.isChatSettingsBusy) {
                    ZappButton(
                        title: String(localizable: store.isChatSettingsBusy ? .chatProfileSaving : .chatProfileSave),
                        isEnabled: store.canSaveChatSettings
                    ) {
                        store.send(.chatSettingsSaveTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack(isEnabled: !store.isChatSettingsBusy, action: onBack)
            .onAppear { store.send(.chatSettingsAppeared) }
        }
    }
}
