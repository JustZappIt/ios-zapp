//
//  SettingsTabContent.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The You tab, mirroring `SettingsTabContent.kt`.
///
/// Only the rows whose subsystem exists on iOS today are rendered. Android also lists chat profile,
/// contacts, app lock, read receipts, online status, background delivery and the p2p payment method;
/// those arrive with chat (Phase 3), PIN (Phase 4) and offramp (Phase 5), each a one-row insert into
/// the group it belongs to.
///
/// `allSettings` is a transitional bridge to the existing settings screen so the address book,
/// advanced settings, about and feedback stay reachable. It retires as those rows are promoted here.
struct SettingsTabContent: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ZappTabs>

    /// nil until chat identity is wired into the app; Android hides the card the same way.
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
                                title: String(localizable: .settingsYouContactsTitle),
                                subtitle: String(localizable: .settingsYouContactsSubtitle),
                                icon: Asset.Assets.Icons.user.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.chatContactsTapped)
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
