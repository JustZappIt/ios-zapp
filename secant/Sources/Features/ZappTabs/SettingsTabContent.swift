//
//  SettingsTabContent.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The You tab, mirroring the grouping of Android main's `SettingsTabContent.kt`.
///
/// App lock routes into the existing `SecuritySettings` feature (verify current PIN/bio, then
/// change PIN / switch auth method), matching Android's Security group. Android's Background
/// delivery row is deliberately absent because push/background delivery is not available on iOS
/// yet. Read receipts and online status open staged detail screens, matching Android without
/// duplicating them in Profile.
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

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsYouAppLockTitle),
                                subtitle: String(localizable: .settingsYouAppLockSubtitle),
                                icon: Asset.Assets.Icons.lockLocked.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.appLockTapped)
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

                        // iOS keeps the "P2P transactions" history row (Appendix B, iOS-only)
                        // alongside Android's payment-method row in this group.
                        ZappSettingsGroup(title: String(localizable: .settingsYouGroupP2p)) {
                            ZappRow(
                                title: String(localizable: .settingsYouP2pPaymentMethodTitle),
                                subtitle: String(localizable: .settingsYouP2pPaymentMethodSubtitle),
                                icon: Asset.Assets.Icons.pay.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.p2pPaymentMethodTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsYouP2pTransactionsTitle),
                                subtitle: String(localizable: .settingsYouP2pTransactionsSubtitle),
                                icon: Asset.Assets.Icons.noTransactions.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.p2pTransactionsTapped)
                            }
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
                    .zappScrollShadowSource()
                }
                .zappScrollEdges()
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
                ChatIdentityQRCode(payload: publicKey, size: Constants.avatarSize)
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
