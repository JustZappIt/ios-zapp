//
//  AboutView.swift
//  Zashi
//
//  Created by Lukáš Korba on 03-13-2023.
//

import SwiftUI
import ComposableArchitecture

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let logoSize: CGFloat = 41
        static let wordmarkWidth: CGFloat = 73
        static let wordmarkHeight: CGFloat = 20
    }

    @Perception.Bindable var store: StoreOf<About>

    init(store: StoreOf<About>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(localizable: .aboutTitle)
                        .zappFont(.displaySecondary, style: ZappColors.text)
                        .padding(.top, Design.Spacing._5xl)

                    Text(localizable: .aboutInfo)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Design.Spacing._lg)

                    Text(localizable: .aboutAdditionalInfo)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Design.Spacing._md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Spacing._lg)

                VStack(spacing: 0) {
                    ZappRow(
                        title: String(localizable: .aboutPrivacyPolicy),
                        icon: Asset.Assets.infoCircle.image,
                        iconTint: .accentText,
                        iconBackground: .accentSoft
                    ) {
                        store.send(.privacyPolicyButtonTapped)
                    }

                    ZappRowDivider(inset: true)

                    ZappRow(
                        title: String(localizable: .aboutTermsOfUse),
                        icon: Asset.Assets.Icons.terms.image,
                        iconTint: .accentText,
                        iconBackground: .accentSoft
                    ) {
                        store.send(.termsOfUseButtonTapped)
                    }
                }
                .background(ZappColors.surface.color(colorScheme))
                .overlay(
                    Rectangle()
                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                )
                .padding(.horizontal, Design.Spacing._lg)
                .padding(.top, Design.Spacing._4xl)

                Spacer()

                Asset.Assets.zashiLogo.image
                    .zImage(width: Constants.logoSize, height: Constants.logoSize, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._sm)

                Asset.Assets.zashiTitle.image
                    .zImage(width: Constants.wordmarkWidth, height: Constants.wordmarkHeight, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._xl)

                Text(localizable: .settingsVersion(store.appVersion, store.appBuild))
                    .zappFont(.caption, style: ZappColors.textSubtle)
                    .padding(.bottom, Design.Spacing._3xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .sheet(isPresented: $store.isInAppBrowserPolicyOn) {
                if let url = URL(string: "https://www.justzappit.xyz/privacy") {
                    InAppBrowserView(url: url)
                }
            }
            .sheet(isPresented: $store.isInAppBrowserTermsOn) {
                if let url = URL(string: "https://www.justzappit.xyz/legal/terms") {
                    InAppBrowserView(url: url)
                }
            }
            .zashiBack()
            .screenTitle(String(localizable: .settingsAbout))
        }
    }
}

// MARK: Placeholders

extension About.State {
    static var initial: About.State { About.State() }
}

extension About {
    @MainActor static let initial = StoreOf<About>(
        initialState: .initial
    ) {
        About()
    }
}

#Preview {
    NavigationView {
        AboutView(store: About.initial)
    }
}
