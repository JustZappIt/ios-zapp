//
//  ChatProfileP2pKeyView.swift
//  Zapp
//
//  Android's `ChatP2pKeyView`: the smart account the P2P cash-outs settle through, shown openly,
//  and the owner key that controls it, locked until "Reveal owner key" passes the app lock.
//
//  Drawn over the profile rather than pushed as its own Root destination, so the profile's
//  secret handling — the PIN pad, and clearing the key on resign-active, background, a screen
//  recording or disappearance — covers it without a second copy. A cleared key relocks the card.
//

import ComposableArchitecture
import SwiftUI

struct ChatProfileP2pKeyView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatProfile>

    @State private var isInfoPresented = false

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .chatProfileP2pKeyTitle)) {
                    ZappInfoButton(accessibilityLabel: String(localizable: .chatP2pKeyInfoButton)) {
                        isInfoPresented = true
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let address = store.p2pSmartAccountAddress {
                            ZappGroupHeader(text: String(localizable: .chatP2pKeySmartAccountLabel))

                            ZappValueCard(
                                value: address,
                                caption: String(localizable: .chatP2pKeySmartAccountCaption)
                            ) {
                                ZappCopyIconButton(
                                    isCopied: store.didCopyP2PSmartAccount,
                                    accessibilityLabel: String(localizable: .chatProfileP2pKeyCopy)
                                ) {
                                    store.send(.copyP2PSmartAccountTapped)
                                }
                            }
                        }

                        ZappGroupHeader(text: String(localizable: .chatP2pKeyOwnerLabel))

                        if let key = store.p2pKey {
                            revealedOwnerKey(key)
                        } else {
                            lockedOwnerKey
                        }
                    }
                    .padding(.bottom, Design.Spacing._xl)
                }

                ZappBottomActionBar(onBack: { store.send(.p2pKeyScreenClosed) })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack(isEnabled: store.pinEntry == nil) { store.send(.p2pKeyScreenClosed) }
            .sheet(isPresented: $isInfoPresented) { infoSheet }
        }
    }

    private var lockedOwnerKey: some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                Text(String(localizable: .chatP2pKeyOwnerLockedBody))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                ZappButton(title: String(localizable: .chatP2pKeyReveal)) {
                    store.send(.p2pKeyRevealTapped)
                }
                .frame(maxWidth: .infinity)

                if store.secretBlockedByCapture {
                    failure(String(localizable: .chatProfileSecretScreenRecording))
                } else if store.secretFailed {
                    failure(String(localizable: .chatProfileSecretFailed))
                }
            }
        }
        .padding(.horizontal, Design.Spacing._lg)
    }

    private func revealedOwnerKey(_ key: OfframpWalletKey) -> some View {
        VStack(spacing: Design.Spacing._lg) {
            ZappValueCard(
                value: key.address,
                label: String(localizable: .chatP2pKeyOwnerAddressLabel),
                caption: String(localizable: .chatP2pKeyOwnerAddressCaption)
            ) {
                ZappCopyIconButton(
                    isCopied: store.didCopyP2PAddress,
                    accessibilityLabel: String(localizable: .chatProfileP2pKeyCopy)
                ) {
                    store.send(.copyP2PAddressTapped)
                }
            }

            ZappValueCard(
                value: key.privateKeyHex.data,
                label: String(localizable: .chatProfileP2pKeyPrivateLabel),
                caption: String(localizable: .chatP2pKeyPrivateKeyCaption)
            ) {
                ZappCopyIconButton(
                    isCopied: store.didCopyP2PKey,
                    accessibilityLabel: String(localizable: .chatProfileP2pKeyCopy)
                ) {
                    store.send(.copyP2PKeyTapped)
                }
            }
        }
    }

    private func failure(_ message: String) -> some View {
        Text(message)
            .zappFont(.caption, style: ZappColors.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            Text(String(localizable: .chatP2pKeyInfoTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            ForEach(
                [
                    String(localizable: .chatP2pKeyInfoDerivation),
                    String(localizable: .chatP2pKeyInfoSmartAccount),
                    String(localizable: .chatP2pKeyInfoSafety)
                ],
                id: \.self
            ) { paragraph in
                Text(paragraph)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zappInfoSheet { isInfoPresented = false }
    }
}
