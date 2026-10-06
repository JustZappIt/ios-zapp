//
//  ChatP2pKeyView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// Android's `ChatP2pKeyView`: the smart-account card, the owner key locked behind the app lock
/// until revealed, and an (i) sheet explaining what the key is.
struct ChatP2pKeyView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let cardGutter: CGFloat = 14
        static let cardSpacing: CGFloat = 12
        static let textGutter: CGFloat = 18
    }

    @Perception.Bindable var store: StoreOf<ChatP2pKey>

    @State private var isInfoPresented = false

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .chatP2pKeyTitle)) {
                    ZappInfoButton(accessibilityLabel: String(localizable: .chatP2pKeyInfoAccessibility)) {
                        isInfoPresented = true
                    }
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if let address = store.smartAccountAddress {
                            ZappGroupHeader(text: String(localizable: .chatP2pKeySmartAccountLabel))

                            ZappValueCard(
                                value: address,
                                caption: String(localizable: .chatP2pKeySmartAccountCaption)
                            ) {
                                copyButton(.smartAccount)
                            }
                        }

                        ZappGroupHeader(text: String(localizable: .chatP2pKeyOwnerLabel))

                        if let key = store.ownerKey {
                            revealedOwnerKey(key)
                        } else {
                            lockedOwnerKey
                        }

                        failureMessage
                    }
                    .padding(.bottom, Design.Spacing._xl)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .accessibilityHidden(store.authGate.pinEntry != nil)
            .zappSwipeBack(isEnabled: store.authGate.pinEntry == nil) { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .sheet(isPresented: $isInfoPresented) {
                ChatP2pKeyInfoSheet { isInfoPresented = false }
            }
            .secretAuthGateOverlay(store: store.scope(state: \.authGate, action: \.authGate))
            .secretScreenGuards(isShowingSecret: store.ownerKey != nil) {
                store.send(.hideSensitiveContent)
            }
        }
    }

    private var lockedOwnerKey: some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: Constants.cardSpacing) {
                Text(localizable: .chatP2pKeyOwnerLockedBody)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                ZappButton(
                    title: String(localizable: .chatP2pKeyReveal),
                    isEnabled: !store.isRevealing
                ) {
                    store.send(.revealTapped)
                }
            }
        }
        .padding(.horizontal, Constants.cardGutter)
    }

    private func revealedOwnerKey(_ key: OfframpWalletKey) -> some View {
        VStack(spacing: Constants.cardSpacing) {
            ZappValueCard(
                value: key.address,
                label: String(localizable: .chatP2pKeyOwnerAddressLabel),
                caption: String(localizable: .chatP2pKeyOwnerAddressCaption)
            ) {
                copyButton(.ownerAddress)
            }

            ZappValueCard(
                value: key.privateKeyHex.data,
                label: String(localizable: .chatP2pKeyPrivateKeyLabel),
                caption: String(localizable: .chatP2pKeyPrivateKeyCaption)
            ) {
                copyButton(.privateKey)
            }
        }
    }

    private func copyButton(_ field: ChatP2pKey.CopiedField) -> some View {
        ZappCopyIconButton(
            isCopied: store.copiedField == field,
            accessibilityLabel: String(localizable: .chatP2pKeyCopy)
        ) {
            store.send(.copyTapped(field))
        }
    }

    @ViewBuilder private var failureMessage: some View {
        if store.keyBlockedByCapture {
            failureText(String(localizable: .chatProfileSecretScreenRecording))
        } else if store.keyFailed {
            failureText(String(localizable: .chatProfileSecretFailed))
        }
    }

    private func failureText(_ message: String) -> some View {
        Text(message)
            .zappFont(.caption, style: ZappColors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Constants.textGutter)
            .padding(.top, Design.Spacing._lg)
    }
}

/// Android's `P2pKeyInfoSheet`: three paragraphs, one tap away from the screen.
private struct ChatP2pKeyInfoSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizable: .chatP2pKeyInfoTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(localizable: .chatP2pKeyInfoDerivation)
                .zappFont(.body, style: ZappColors.textMuted)

            Text(localizable: .chatP2pKeyInfoSmartAccount)
                .zappFont(.body, style: ZappColors.textMuted)

            Text(localizable: .chatP2pKeyInfoSafety)
                .zappFont(.body, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .zappInfoSheet(onDismiss: onDismiss)
    }
}

#Preview {
    ChatP2pKeyView(store: ChatP2pKey.initial)
}
