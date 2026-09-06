//
//  ChatSettingsView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The three chat preferences gathered on one screen, as Android's `ChatSettingsView` gathers
/// them: privacy (read receipts, online status) above delivery (background alerts).
///
/// Android stages the edits behind a Save button. iOS applies each toggle immediately, which is
/// what every other toggle in this app does and what the platform's own Settings do — the reducer
/// already holds the optimistic value and a per-setting busy flag, so there is nothing to stage.
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
                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupPrivacy)) {
                            ZappToggleRow(
                                title: String(localizable: .chatPrivacyReadReceiptsToggleTitle),
                                subtitle: String(localizable: .chatPrivacyReadReceiptsToggleSubtitle),
                                icon: Asset.Assets.Icons.checkSolid.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.readReceiptsEnabled,
                                isEnabled: !store.isReadReceiptsBusy
                            ) {
                                store.send(.readReceiptsToggled)
                            }

                            ZappRowDivider(inset: true)

                            ZappToggleRow(
                                title: String(localizable: .chatPrivacyOnlineStatusToggleTitle),
                                subtitle: String(localizable: .chatPrivacyOnlineStatusToggleSubtitle),
                                icon: Asset.Assets.Icons.user.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.presenceVisible,
                                isEnabled: !store.isPresenceBusy
                            ) {
                                store.send(.presenceToggled)
                            }
                        }

                        ZappSettingsGroup(title: String(localizable: .chatSettingsSectionDelivery)) {
                            ZappToggleRow(
                                title: String(localizable: .chatNotificationsBackgroundTitle),
                                subtitle: String(localizable: .chatNotificationsBackgroundSubtitle),
                                icon: Asset.Assets.Icons.messageChat.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.backgroundNotificationsEnabled,
                                isEnabled: !store.isBackgroundNotificationsBusy
                            ) {
                                store.send(.backgroundNotificationsToggled)
                            }
                        }
                    }
                    .padding(.vertical, Design.Spacing._xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(customDismiss: onBack)
        }
    }
}
