//
//  SettingsTabContent.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The You tab, mirroring the grouping of Android main's `SettingsTabContent.kt`.
///
/// Android's App lock and Background delivery rows are deliberately absent because those
/// subsystems are not available on iOS yet. Read receipts and online status open staged detail
/// screens, matching Android without duplicating them in Profile.
///
/// `allSettings` is iOS's route to the address book, advanced settings, about,
/// feedback and voting. Keeping it here preserves those working surfaces without
/// editing upstream's Settings reducer.
struct SettingsTabContent: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ZappTabs>
    @Perception.Bindable var chatProfileStore: StoreOf<ChatProfile>

    /// nil until the chat identity resolves; Android hides the card the same way.
    var displayName: String?

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .settingsYouTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        if let displayName {
                            ProfileCard(
                                displayName: displayName,
                                publicKey: chatProfileStore.publicKey
                            )
                        }

                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupPeople)) {
                            ZappRow(
                                title: String(localizable: .settingsYouContactsTitle),
                                subtitle: String(localizable: .settingsYouContactsSubtitleNew),
                                icon: Asset.Assets.Icons.userPlus.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.chatContactsTapped)
                            }
                        }

                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupSecurity)) {
                            ZappRow(
                                title: String(localizable: .settingsYouProfileIdentityTitle),
                                subtitle: String(localizable: .settingsYouProfileIdentitySubtitle),
                                icon: Asset.Assets.Icons.user.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.chatProfileTapped)
                            }
                        }

                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupPrivacy)) {
                            ZappToggleRow(
                                title: String(
                                    localized: "chat.notifications.background.title",
                                    defaultValue: "Background chat alerts"
                                ),
                                subtitle: String(
                                    localized: "chat.notifications.background.subtitle",
                                    defaultValue: "Get a private alert when a direct message arrives"
                                ),
                                icon: Asset.Assets.Icons.messageChat.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: chatProfileStore.backgroundNotificationsEnabled,
                                isEnabled: !chatProfileStore.isBackgroundNotificationsBusy
                            ) {
                                chatProfileStore.send(.backgroundNotificationsToggled)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsYouTorTitle),
                                subtitle: String(localizable: .settingsYouTorSubtitle),
                                icon: Asset.Assets.shield.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.torTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localized: "offramp.paymentMethod", defaultValue: "P2P payment method"),
                                subtitle: String(
                                    localized: "offramp.paymentMethod.subtitle",
                                    defaultValue: "Choose your country and local payment rail"
                                ),
                                icon: Asset.Assets.Icons.pay.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.p2pPaymentMethodTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localized: "offramp.history.title", defaultValue: "P2P transactions"),
                                subtitle: String(
                                    localized: "offramp.history.subtitle",
                                    defaultValue: "View payments and recover cancelled orders"
                                ),
                                icon: Asset.Assets.Icons.noTransactions.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.p2pTransactionsTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .chatProfileReadReceipts),
                                subtitle: String(localizable: .chatProfileReadReceiptsHint),
                                icon: Asset.Assets.Icons.checkSolid.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) { store.send(.readReceiptsTapped) }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .chatProfilePresence),
                                subtitle: String(localizable: .chatProfilePresenceHint),
                                icon: Asset.Assets.Icons.user.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) { store.send(.onlineStatusTapped) }
                        }

                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupWallet)) {
                            ZappRow(
                                title: String(localizable: .settingsYouLocalCurrencyTitle),
                                subtitle: String(localizable: .settingsYouLocalCurrencySubtitle),
                                icon: Asset.Assets.Icons.currencyDollar.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.localCurrencyTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsYouServerTitle),
                                subtitle: String(localizable: .settingsYouServerSubtitle),
                                icon: Asset.Assets.Icons.server.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.chooseServerTapped)
                            }
                        }

                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupMore)) {
                            ZappRow(
                                title: String(localizable: .settingsYouAllSettingsTitle),
                                subtitle: String(localizable: .settingsYouAllSettingsSubtitle),
                                icon: Asset.Assets.Icons.settings.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.allSettingsTapped)
                            }
                        }
                    }
                    .padding(.bottom, ZappNavBar.clearance)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { chatProfileStore.send(.onAppear) }
            .onDisappear { chatProfileStore.send(.onDisappear) }
        }
    }
}

private struct ProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 80
    }

    let displayName: String
    let publicKey: String

    var body: some View {
        VStack(spacing: Design.Spacing._md) {
            // Initials until the identity resolves: an empty QR frame reads as a broken image.
            if publicKey.isEmpty {
                Text(displayName.zappInitials)
                    .zappFont(.sectionTitle, style: ZappColors.onAccent)
                    .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                    .background(ZappColors.accent.color(colorScheme))
            } else {
                ChatIdentityQRCode(publicKey: publicKey, size: Constants.avatarSize)
                    .accessibilityLabel(String(localizable: .settingsProfileQRCode))
            }

            Text("@\(displayName)")
                .zappFont(.sectionTitle, style: ZappColors.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

#Preview {
    SettingsTabContent(
        store: ZappTabs.initial,
        chatProfileStore: ChatProfile.initial,
        displayName: "chinmay"
    )
}
