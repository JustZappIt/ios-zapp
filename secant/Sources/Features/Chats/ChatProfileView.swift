//
//  ChatProfileView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI
import UIKit

struct ChatProfileView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatProfile>

    private let isYouRoot: Bool
    private let onBack: () -> Void
    private let onSettings: (() -> Void)?

    /// Pushed presentation retained for any existing deep link or settings route.
    init(store: StoreOf<ChatProfile>) {
        self.store = store
        self.isYouRoot = false
        self.onBack = { store.send(.backToHomeTapped) }
        self.onSettings = nil
    }

    /// Android's profile-first You tab: no duplicate title, no floating nav pill,
    /// and a bottom dock that returns to the previous tab or opens Settings.
    init(
        store: StoreOf<ChatProfile>,
        onBack: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.store = store
        self.isYouRoot = true
        self.onBack = onBack
        self.onSettings = onSettings
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                if !isYouRoot {
                    ZappScreenHeader(title: String(localizable: .chatProfileTitle)) {
                        ZappBackButton(action: onBack)
                    } right: {
                        EmptyView()
                    }
                }

                ScrollView {
                    VStack(spacing: 0) {
                        identityHero
                            .padding(.bottom, Design.Spacing._lg)

                        if store.hasPublicKey {
                            qrCard
                                .padding(.bottom, Design.Spacing._lg)

                            publicKeyCard
                                .padding(.bottom, Design.Spacing._lg)
                        }

                        displayNameGroup
                    }
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, Design.Spacing._md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isYouRoot, let onSettings {
                    ZappBottomActionBar(onBack: onBack) {
                        ZappButton(
                            title: String(localizable: .settingsTitle),
                            variant: .secondary,
                            leadingIcon: Asset.Assets.Icons.settings.image,
                            action: onSettings
                        )
                    }
                }
            }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    private var identityHero: some View {
        VStack(spacing: Design.Spacing._sm) {
            Text(store.displayName.zappInitials)
                .zappFont(.sectionTitle, style: ZappColors.onAccent)
                .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                .background(ZappColors.accent.color(colorScheme))

            Text(store.displayName)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(Constants.nameMinimumScale)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Constants.screenInset)
    }

    private var qrCard: some View {
        VStack(spacing: Design.Spacing._sm) {
            ChatIdentityQRCode(publicKey: store.publicKey)

            Text(String(localizable: .chatProfileQrCaption))
                .zappFont(.caption, style: ZappColors.textSubtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Design.Spacing._lg)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, Constants.screenInset)
    }

    private var publicKeyCard: some View {
        HStack(spacing: Design.Spacing._sm) {
            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                Text(String(localizable: .chatProfilePublicKey))
                    .zappFont(.caption, style: ZappColors.textMuted)

                Text(store.publicKey)
                    .zappFont(.mono, style: ZappColors.text)
                    .lineLimit(Constants.publicKeyLineLimit)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.send(.copyPublicKeyTapped)
            } label: {
                (store.didCopy ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image)
                    .zImage(
                        width: Constants.copyIconSize,
                        height: Constants.copyIconSize,
                        style: store.didCopy ? ZappColors.success : ZappColors.textMuted
                    )
                    .frame(width: Constants.touchTarget, height: Constants.touchTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(
                store.didCopy
                    ? String(localizable: .newChatCopied)
                    : String(localizable: .newChatCopy)
            )
        }
        .padding(Design.Spacing._lg)
        .background(ZappColors.surfaceAlt.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, Constants.screenInset)
    }

    private var displayNameGroup: some View {
        ChatProfileGroup(title: String(localizable: .chatProfileDisplayName)) {
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                TextField(
                    String(localizable: .chatProfileDisplayName),
                    text: Binding(
                        get: { store.displayName },
                        set: { store.send(.displayNameChanged($0)) }
                    )
                )
                .zappFont(.body, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(Design.Spacing._md)
                .background(ZappColors.surfaceInput.color(colorScheme))

                Text(String(localizable: .chatProfileDisplayNameHint))
                    .zappFont(.caption, color: ZappColors.textMuted.color(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if store.saveFailed {
                    Text(String(localizable: .chatProfileSaveFailed))
                        .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ZappButton(
                    title: String(localizable: .chatProfileSave),
                    isEnabled: store.canSave
                ) {
                    store.send(.saveTapped)
                }
            }
            .padding(ChatProfileGroupConstants.contentPadding)
        }
    }

}

private extension ChatProfileView {
    enum Constants {
        static let avatarSize: CGFloat = 72
        static let copyIconSize: CGFloat = 20
        static let nameMinimumScale: CGFloat = 0.75
        static let publicKeyLineLimit = 3
        static let screenInset: CGFloat = 18
        static let touchTarget: CGFloat = 48
    }
}

private struct ChatIdentityQRCode: View {
    private enum Constants {
        static let size: CGFloat = 176
    }

    let publicKey: String
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.white)
            }
        }
        .frame(width: Constants.size, height: Constants.size)
        .background(Color.white)
        .task(id: publicKey) {
            guard !publicKey.isEmpty else {
                image = nil
                return
            }

            image = await QRCodeGenerator.generate(
                from: publicKey,
                maxPrivacy: false,
                color: .black,
                overlayedWithZcashLogo: false
            )
        }
    }
}

private struct ChatProfileGroup<Content: View>: View {
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
            .padding(.horizontal, ChatProfileGroupConstants.horizontalInset)

            Spacer()
                .frame(height: Design.Spacing._md)
        }
    }
}

private enum ChatProfileGroupConstants {
    static let contentPadding: CGFloat = 18
    static let horizontalInset: CGFloat = 14
}

#Preview {
    ChatProfileView(
        store: ChatProfile.initial,
        onBack: { },
        onSettings: { }
    )
}
