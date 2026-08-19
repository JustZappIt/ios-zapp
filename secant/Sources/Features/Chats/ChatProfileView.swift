//
//  ChatProfileView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// Android's `ChatProfileView`: one page — the name, the key, what the identity is made of, and
/// the one action that destroys it. The scannable code lives on the You tab.
struct ChatProfileView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let editIconSize: CGFloat = 14
        static let touchTarget: CGFloat = 48
        static let nameMinimumScale: CGFloat = 0.75
        static let screenInset: CGFloat = 18
    }

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
                        displayNameRow
                            .padding(.bottom, Design.Spacing._lg)

                        if store.hasPublicKey {
                            ZappValueCard(
                                value: store.publicKey,
                                label: String(localizable: .chatProfilePublicKey)
                            )
                        }

                        identityGroup
                            .padding(.top, Design.Spacing._md)

                        dangerZone
                    }
                    .padding(.top, Design.Spacing._md)
                    .padding(.bottom, Design.Spacing._xl)
                }

                ZappBottomActionBar(onBack: { store.send(.backToHomeTapped) }) {
                    ZappButton(
                        title: store.didCopy
                            ? String(localizable: .newChatCopied)
                            : String(localizable: .chatProfileCopyPublicKey),
                        isEnabled: store.hasPublicKey,
                        leadingIcon: store.didCopy
                            ? Asset.Assets.Icons.checkSolid.image
                            : Asset.Assets.copy.image
                    ) {
                        store.send(.copyPublicKeyTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            // Applied before the overlays below, so the page goes out of VoiceOver's reach while
            // one of them is up and the overlay itself stays reachable.
            .accessibilityHidden(store.isModalPresented)
            .zappSwipeBack(isEnabled: !store.isModalPresented) { store.send(.backToHomeTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .overlay {
                if let editName = store.editName {
                    ChatProfileEditNameDialog(
                        editName: editName,
                        onChange: { store.send(.editDisplayNameChanged($0)) },
                        onSave: { store.send(.editDisplayNameSaveTapped) },
                        onDismiss: { store.send(.editDisplayNameDismissed) }
                    )
                }
            }
            .chatProfileSecretOverlays(store: store)
        }
    }

    private var displayNameRow: some View {
        HStack(spacing: Design.Spacing._xs) {
            Text("@\(store.displayName)")
                .zappFont(.sectionTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(Constants.nameMinimumScale)

            Button { store.send(.editDisplayNameTapped) } label: {
                Asset.Assets.Icons.pencil.image
                    .zImage(
                        width: Constants.editIconSize,
                        height: Constants.editIconSize,
                        style: ZappColors.textMuted
                    )
                    .frame(width: Constants.touchTarget, height: Constants.touchTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .chatProfileEditDisplayName))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Constants.screenInset)
    }

    /// Android's Identity group. The seed backs up both identities and the P2P key belongs to the
    /// wallet behind them, so both rows are offered unconditionally — as is the address screen,
    /// which handles its own "not ready yet".
    private var identityGroup: some View {
        ZappSettingsGroup(title: String(localizable: .chatProfileGroupIdentity)) {
            ZappRow(
                title: String(localizable: .chatWalletAddressTitle),
                subtitle: String(localizable: .chatWalletAddressSubtitle),
                icon: Asset.Assets.Icons.qr.image,
                iconTint: .accentText,
                iconBackground: .accentSoft
            ) {
                store.send(.walletAddressTapped)
            }

            ZappRowDivider(inset: true)

            ZappRow(
                title: String(localizable: .chatProfileSeedPhraseTitle),
                subtitle: String(localizable: .chatProfileSeedPhraseSubtitle),
                icon: Asset.Assets.Icons.key.image,
                iconTint: .accentText,
                iconBackground: .accentSoft
            ) {
                store.send(.seedPhraseTapped)
            }

            ZappRowDivider(inset: true)

            ZappRow(
                title: String(localizable: .chatProfileP2pKeyTitle),
                subtitle: String(localizable: .chatProfileP2pKeySubtitle),
                icon: Asset.Assets.Icons.connectWallet.image,
                iconTint: .accentText,
                iconBackground: .accentSoft
            ) {
                store.send(.p2pKeyTapped)
            }

            secretFailure
        }
    }

    @ViewBuilder private var secretFailure: some View {
        if store.secretBlockedByCapture {
            secretFailureMessage(String(localizable: .chatProfileSecretScreenRecording))
        } else if store.secretFailed {
            secretFailureMessage(String(localizable: .chatProfileSecretFailed))
        }
    }

    private func secretFailureMessage(_ message: String) -> some View {
        Text(message)
            .zappFont(.caption, style: ZappColors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Design.Spacing._lg)
    }

    private var dangerZone: some View {
        ZappSettingsGroup(title: String(localizable: .chatProfileGroupDangerZone)) {
            ZappRow(
                title: String(localizable: .chatProfileDeleteButton),
                subtitle: String(localizable: .chatProfileDeleteIdentitySubtitle),
                titleColor: .danger
            ) {
                store.send(.deleteIdentityTapped)
            }
        }
    }
}

#Preview {
    ChatProfileView(store: ChatProfile.initial)
}
