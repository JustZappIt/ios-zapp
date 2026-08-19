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

    @State private var enlargedPublicKey: String?

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .settingsYouTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        // Both halves or neither: a blank code frame reads as a broken image, and
                        // a legacy identity with an empty name would render a bare "@".
                        if let displayName, !displayName.isEmpty, chatProfileStore.hasPublicKey {
                            ProfileCard(
                                displayName: displayName,
                                publicKey: chatProfileStore.publicKey,
                                didCopy: chatProfileStore.didCopy,
                                onQRTap: { enlargedPublicKey = chatProfileStore.publicKey },
                                onCopyKey: { chatProfileStore.send(.copyPublicKeyTapped) }
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
                                title: String(localizable: .settingsPortfolioChartTitle),
                                subtitle: String(localizable: .settingsPortfolioChartSubtitle),
                                icon: Asset.Assets.Icons.currencyDollar.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.portfolioChartTapped)
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
            // The nav pill draws above this tab's content, so it would otherwise float over the
            // enlarged code.
            .onChange(of: enlargedPublicKey) { store.send(.fullscreenChanged($0 != nil)) }
            .zappQRSpotlight(payload: $enlargedPublicKey) { payload, edge in
                ChatIdentityQRCode(payload: payload, size: edge)
            } action: { _ in
                ZappButton(title: copyKeyTitle, leadingIcon: copyKeyIcon) {
                    chatProfileStore.send(.copyPublicKeyTapped)
                }
            }
        }
    }

    private var copyKeyTitle: String {
        chatProfileStore.didCopy
            ? String(localizable: .newChatCopied)
            : String(localizable: .settingsProfileCopyKey)
    }

    private var copyKeyIcon: Image {
        chatProfileStore.didCopy ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image
    }
}

/// Android's `ProfileCard`: the code, the handle, and a compact key-copy action under it.
private struct ProfileCard: View {
    private enum Constants {
        static let qrSize: CGFloat = 109
        static let nameSpacing: CGFloat = 6
        static let nameMinimumScale: CGFloat = 0.75
        static let screenInset: CGFloat = 18
        static let topInset: CGFloat = 4
    }

    let displayName: String
    let publicKey: String
    let didCopy: Bool
    let onQRTap: () -> Void
    let onCopyKey: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onQRTap) {
                ChatIdentityQRCode(payload: publicKey, size: Constants.qrSize)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .settingsProfileQRCode))

            Text("@\(displayName)")
                .zappFont(.sectionTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(Constants.nameMinimumScale)
                .padding(.top, Constants.nameSpacing)

            ZappStatusChip(
                text: didCopy
                    ? String(localizable: .newChatCopied)
                    : String(localizable: .settingsProfileCopyKey),
                variant: didCopy ? .success : .outlined,
                leadingIcon: didCopy ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image,
                action: onCopyKey
            )
            .padding(.top, Design.Spacing._md)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Constants.screenInset)
        .padding(.top, Constants.topInset)
    }
}

#Preview {
    SettingsTabContent(
        store: ZappTabs.initial,
        chatProfileStore: ChatProfile.initial,
        displayName: "chinmay"
    )
}
