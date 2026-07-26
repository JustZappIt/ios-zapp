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

    init(store: StoreOf<ChatProfile>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .chatProfileTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        tabSelector
                            .padding(.horizontal, Constants.screenInset)
                            .padding(.bottom, Design.Spacing._lg)

                        switch store.activeTab {
                        case .messagingID:
                            messagingIDTab
                        case .walletAddress:
                            walletAddressTab
                        }

                        keyExportRows
                            .padding(.top, Design.Spacing._lg)

                        deleteIdentity
                            .padding(.top, Design.Spacing._lg)
                    }
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, Design.Spacing._md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(customDismiss: { store.send(.backToHomeTapped) })
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .chatProfileSecretOverlays(store: store)
        }
    }

    // MARK: Tabs

    private var tabSelector: some View {
        VStack(spacing: Design.Spacing._sm) {
            ZappSegmentedSelector(
                options: [
                    String(localizable: .chatProfileTabMessagingId),
                    String(localizable: .chatProfileTabWalletAddress)
                ],
                selectedIndex: store.activeTab.rawValue
            ) { index in
                store.send(.tabSelected(index == 0 ? .messagingID : .walletAddress))
            }

            if store.showsWalletSubTabs {
                ZappSegmentedSelector(
                    options: [
                        String(localizable: .chatProfileSubtabShielded),
                        String(localizable: .chatProfileSubtabTransparent)
                    ],
                    selectedIndex: store.walletSubTab.rawValue
                ) { index in
                    store.send(.walletSubTabSelected(index == 0 ? .shielded : .transparent))
                }
            }
        }
    }

    @ViewBuilder private var messagingIDTab: some View {
        identityHero
            .padding(.bottom, Design.Spacing._lg)

        if store.hasPublicKey {
            qrCard(payload: store.publicKey, caption: String(localizable: .chatProfileQrCaption))
                .padding(.bottom, Design.Spacing._lg)

            valueCard(
                label: String(localizable: .chatProfilePublicKey),
                value: store.publicKey,
                didCopy: store.didCopy,
                copyLabel: String(localizable: .newChatCopy)
            ) {
                store.send(.copyPublicKeyTapped)
            }
            .padding(.bottom, Design.Spacing._lg)
        }

        displayNameGroup
    }

    @ViewBuilder private var walletAddressTab: some View {
        if let address = store.selectedWalletAddress, !address.isEmpty {
            qrCard(payload: address, caption: addressCaption)
                .padding(.bottom, Design.Spacing._lg)

            valueCard(
                label: addressLabel,
                value: address,
                didCopy: store.didCopyAddress,
                copyLabel: String(localizable: .chatProfileCopyAddress)
            ) {
                store.send(.copyAddressTapped)
            }
        } else {
            Text(String(localizable: .chatProfileAddressUnavailable))
                .zappFont(.caption, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Constants.screenInset)
        }
    }

    private var addressLabel: String {
        store.walletSubTab == .shielded
            ? String(localizable: .chatProfileAddressShieldedLabel)
            : String(localizable: .chatProfileAddressTransparentLabel)
    }

    private var addressCaption: String {
        store.walletSubTab == .shielded
            ? String(localizable: .chatProfileAddressShieldedCaption)
            : String(localizable: .chatProfileAddressTransparentCaption)
    }

    // MARK: Cards

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

    private func qrCard(payload: String, caption: String) -> some View {
        VStack(spacing: Design.Spacing._sm) {
            ChatProfileQRCode(payload: payload)

            Text(caption)
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

    private func valueCard(
        label: String,
        value: String,
        didCopy: Bool,
        copyLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Design.Spacing._sm) {
            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                Text(label)
                    .zappFont(.caption, style: ZappColors.textMuted)

                Text(value)
                    .zappFont(.mono, style: ZappColors.text)
                    .lineLimit(Constants.valueLineLimit)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                (didCopy ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image)
                    .zImage(
                        width: Constants.copyIconSize,
                        height: Constants.copyIconSize,
                        style: didCopy ? ZappColors.success : ZappColors.textMuted
                    )
                    .frame(width: Constants.touchTarget, height: Constants.touchTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(didCopy ? String(localizable: .newChatCopied) : copyLabel)
        }
        .padding(Design.Spacing._lg)
        .background(ZappColors.surfaceAlt.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, Constants.screenInset)
    }
}

// MARK: - Secrets, delete & display name

private extension ChatProfileView {
    /// Android's `KeyExportRows`: the seed backs up both identities so it is always offered; the
    /// P2P key belongs to the wallet, so it only appears on the wallet tab.
    var keyExportRows: some View {
        VStack(spacing: 0) {
            ZappRow(
                title: String(localizable: .chatProfileSeedPhraseTitle),
                subtitle: String(localizable: .chatProfileSeedPhraseSubtitle),
                icon: Asset.Assets.Icons.key.image,
                iconTint: .accent
            ) {
                store.send(.seedPhraseTapped)
            }

            if store.showsP2PKeyRow {
                ZappRowDivider(inset: true)

                ZappRow(
                    title: String(localizable: .chatProfileP2pKeyTitle),
                    subtitle: String(localizable: .chatProfileP2pKeySubtitle),
                    icon: Asset.Assets.Icons.connectWallet.image,
                    iconTint: .accent
                ) {
                    store.send(.p2pKeyTapped)
                }
            }

            if store.secretFailed {
                Text(String(localizable: .chatProfileSecretFailed))
                    .zappFont(.caption, style: ZappColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._md)
            }
        }
        .background(ZappColors.surface.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, Constants.screenInset)
    }

    var deleteIdentity: some View {
        ZappButton(title: String(localizable: .chatProfileDeleteButton), variant: .danger) {
            store.send(.deleteIdentityTapped)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Constants.screenInset)
    }

    var displayNameGroup: some View {
        ZappSettingsGroup(title: String(localizable: .chatProfileDisplayName)) {
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
            .padding(Constants.contentPadding)
        }
    }
}

private extension ChatProfileView {
    enum Constants {
        static let avatarSize: CGFloat = 72
        static let copyIconSize: CGFloat = 20
        static let nameMinimumScale: CGFloat = 0.75
        static let valueLineLimit = 3
        static let screenInset: CGFloat = 18
        static let touchTarget: CGFloat = 48
        static let contentPadding: CGFloat = 18
    }
}

struct ChatProfileQRCode: View {
    private enum Constants {
        static let size: CGFloat = 176
    }

    let payload: String
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
        .task(id: payload) {
            guard !payload.isEmpty else {
                image = nil
                return
            }

            image = await QRCodeGenerator.generate(
                from: payload,
                maxPrivacy: false,
                color: .black,
                overlayedWithZcashLogo: false
            )
        }
    }
}

#Preview {
    ChatProfileView(store: ChatProfile.initial)
}
