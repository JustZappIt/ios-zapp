//
//  IronwoodAnnouncementView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

// Zapp's existing Ironwood guide, linked from the product FAQ. Both entry
// points intentionally use the same first-party Zapp article.
private let ironwoodAnnouncementFAQURL = "https://www.justzappit.xyz/ironwood"

struct IronwoodAnnouncementView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Perception.Bindable var store: StoreOf<IronwoodAnnouncement>

    init(store: StoreOf<IronwoodAnnouncement>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                // The copy scrolls independently so the actions remain
                // reachable on small devices and with longer translations.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: -3) {
                            Asset.Assets.zappLogo.image
                                .resizable()
                                .frame(width: 48, height: 48)

                            Asset.Assets.zcashZecLogo.image
                                .resizable()
                                .frame(width: 48, height: 48)
                        }
                        .padding(.top, Design.Spacing._lg)

                        Text(localizable: .ironwoodAnnouncementTitle)
                            .zappFont(.displaySecondary, style: ZappColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Design.Spacing._xl)

                        Text(localizable: .ironwoodAnnouncementBody1)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Design.Spacing._lg)

                        Text(localizable: .ironwoodAnnouncementBody2)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Design.Spacing._lg)

                        Text(localizable: .ironwoodAnnouncementBody3)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Design.Spacing._lg)

                        Text(guideAttributedString())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Design.Spacing._3xl)
                            .environment(\.openURL, OpenURLAction { _ in
                                store.send(.guideTapped)
                                return .handled
                            })
                    }
                }
                .scrollBounceBasedOnSizeIfAvailable()

                Spacer()

                // The screen's ONLY button, pinned outside the scroll view, and the only
                // way to acknowledge the announcement. "Learn more" stood above it until
                // 2026-08-08 (Lukas): it opened the very same support article the inline guide
                // link opens — the store's own arms were byte-identical — so the duplicate was
                // removed and the guide link is now the single route to the article. What
                // remains is one dismiss.
                ZappButton(title: String(localizable: .ironwoodAnnouncementContinue)) {
                    store.send(.continueTapped)
                }
                .padding(.bottom, Design.Spacing._3xl)
            }
            .padding(.top, 60)
            .sheet(isPresented: $store.isInAppBrowserOn) {
                if let url = URL(string: ironwoodAnnouncementFAQURL) {
                    InAppBrowserView(url: url)
                }
            }
        }
        .navigationBarHidden(true)
        .screenHorizontalPadding()
        .applyScreenBackground()
    }

    private func guideAttributedString() -> AttributedString {
        var prefix = AttributedString(String(localizable: .ironwoodAnnouncementGuidePrefix))
        prefix.font = Font.custom(FontFamily.Inter.regular.name, size: 14)
        prefix.foregroundColor = ZappColors.text.color(colorScheme)

        var link = AttributedString(String(localizable: .ironwoodAnnouncementGuideLink))
        link.font = Font.custom(FontFamily.Inter.semiBold.name, size: 14)
        link.underlineStyle = .single
        link.foregroundColor = ZappColors.accentText.color(colorScheme)
        link.link = URL(string: ironwoodAnnouncementFAQURL)

        var suffix = AttributedString(String(localizable: .ironwoodAnnouncementGuideSuffix))
        suffix.font = Font.custom(FontFamily.Inter.regular.name, size: 14)
        suffix.foregroundColor = ZappColors.text.color(colorScheme)

        return prefix + link + suffix
    }
}

private extension View {
    @ViewBuilder
    func scrollBounceBasedOnSizeIfAvailable() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

#Preview {
    NavigationView {
        IronwoodAnnouncementView(store: IronwoodAnnouncement.initial)
    }
}

extension IronwoodAnnouncement {
    @MainActor static let initial = StoreOf<IronwoodAnnouncement>(
        initialState: .initial
    ) {
        IronwoodAnnouncement()
    }
}

extension IronwoodAnnouncement.State {
    static let initial = IronwoodAnnouncement.State()
}
