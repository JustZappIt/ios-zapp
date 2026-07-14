//
//  SettingsTabContent.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The You tab, mirroring the grouping of `SettingsTabContent.kt`.
///
/// Android's App lock, Background delivery, Read receipts, Online status and P2P payment method rows
/// are deliberately absent: each fronts a subsystem iOS does not have yet, and the receipts/presence
/// toggles already live inside Chat profile. A row that opens nothing is worse than no row.
///
/// `allSettings` has no Android counterpart — Android's own MoreScreen is unreachable from the Zapp
/// shell, which is a bug there, not a target. It is the only route to the address book, advanced
/// settings, about, feedback and voting, all of which have working iOS screens.
struct SettingsTabContent: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ZappTabs>

    /// nil until the chat identity resolves; Android hides the card the same way.
    var displayName: String?

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .settingsYouTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        if let displayName {
                            ProfileCard(displayName: displayName)
                        }

                        SettingsGroup(title: String(localizable: .settingsYouGroupPeople)) {
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

                        SettingsGroup(title: String(localizable: .settingsYouGroupSecurity)) {
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

                        SettingsGroup(title: String(localizable: .settingsYouGroupPrivacy)) {
                            ZappRow(
                                title: String(localizable: .settingsYouTorTitle),
                                subtitle: String(localizable: .settingsYouTorSubtitle),
                                icon: Asset.Assets.shield.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.torTapped)
                            }
                        }

                        SettingsGroup(title: String(localizable: .settingsYouGroupWallet)) {
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

                        SettingsGroup(title: String(localizable: .settingsYouGroupMore)) {
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
        }
    }
}

private struct ProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 72
    }

    let displayName: String

    var body: some View {
        VStack(spacing: Design.Spacing._md) {
            Text(displayName.zappInitials)
                .zappFont(.sectionTitle, style: ZappColors.onAccent)
                .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                .background(ZappColors.accent.color(colorScheme))

            Text("@\(displayName)")
                .zappFont(.sectionTitle, style: ZappColors.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: title)

            VStack(spacing: 0) {
                content
            }
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, 14)

            Spacer()
                .frame(height: Design.Spacing._md)
        }
    }
}

#Preview {
    SettingsTabContent(store: ZappTabs.initial, displayName: "chinmay")
}
