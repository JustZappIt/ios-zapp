//
//  ChatContactFormView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ChatContactFormView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let closeTouchTarget: CGFloat = 48
        static let closeIconSize: CGFloat = 20
        static let scanIconSize: CGFloat = 20
        static let disclosureIconSize: CGFloat = 12
    }

    @Perception.Bindable var store: StoreOf<ChatContactForm>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: title) {
                    closeButton
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                        nameField
                        keyField
                        addressField
                        additionalAddresses

                        if store.isBlocked {
                            Text(String(localizable: .chatContactsBlockedNotice))
                                .zappFont(.caption, style: ZappColors.danger)
                        }

                        buttons
                    }
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .fullScreenCover(item: $store.scope(state: \.scan, action: \.scan)) { scanStore in
                WithPerceptionTracking {
                    ScanView(store: scanStore)
                }
            }
        }
    }

    private var title: String {
        store.isEditing
            ? String(localizable: .chatContactsEdit)
            : String(localizable: .chatContactsAdd)
    }

    private var closeButton: some View {
        Button {
            store.send(.closeTapped)
        } label: {
            Asset.Assets.Icons.xClose.image
                .zImage(width: Constants.closeIconSize, height: Constants.closeIconSize, style: ZappColors.text)
                .frame(width: Constants.closeTouchTarget, height: Constants.closeTouchTarget)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(String(localizable: .generalClose))
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .chatContactsNameLabel))

            TextField(
                String(localizable: .chatContactsNamePlaceholder),
                text: Binding(
                    get: { store.name },
                    set: { store.send(.nameChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .autocorrectionDisabled()
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .chatContactsKeyLabel))

            if store.isKeyLocked {
                Text(store.publicKey)
                    .zappFont(.mono, style: ZappColors.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._md)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
            } else {
                HStack(spacing: 0) {
                    TextField(
                        String(localizable: .newChatPeerPlaceholder),
                        text: Binding(
                            get: { store.publicKey },
                            set: { store.send(.publicKeyChanged($0)) }
                        ),
                        axis: .vertical
                    )
                    .zappFont(.mono, style: ZappColors.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2, reservesSpace: true)
                    .padding(Design.Spacing._md)

                    scanButton(
                        target: .publicKey,
                        accessibilityLabel: String(localizable: .chatContactsScanKey)
                    )
                }
                .background(ZappColors.surfaceInput.color(colorScheme))
            }

            if store.showsInvalidKeyHint {
                Text(String(localizable: .newChatInvalidKey))
                    .zappFont(.caption, style: ZappColors.danger)
            }

            if store.isDuplicateKey {
                Text(String(localizable: .chatContactsDuplicate))
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .chatContactsAddressLabel))

            HStack(spacing: 0) {
                TextField(
                    String(localizable: .chatContactsAddressPlaceholder),
                    text: Binding(
                        get: { store.address },
                        set: { store.send(.addressChanged($0)) }
                    ),
                    axis: .vertical
                )
                .zappFont(.mono, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2, reservesSpace: true)
                .padding(Design.Spacing._md)

                scanButton(
                    target: .address,
                    accessibilityLabel: String(localizable: .chatContactsScanAddress)
                )
            }
            .background(ZappColors.surfaceInput.color(colorScheme))

            if !store.isValidAddress {
                Text(String(localizable: .chatContactsInvalidAddress))
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: Design.Spacing._md) {
            ZappButton(title: String(localizable: .chatContactsSave), isEnabled: store.canSave) {
                store.send(.saveTapped)
            }
            .frame(maxWidth: .infinity)

            if store.canBlock {
                ZappButton(title: blockTitle, variant: .secondary) {
                    store.send(.blockTapped)
                }
                .frame(maxWidth: .infinity)
            }

            if store.isEditing {
                ZappButton(title: String(localizable: .chatContactsDelete), variant: .danger) {
                    store.send(.deleteTapped)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var blockTitle: String {
        store.isBlocked
            ? String(localizable: .chatContactsUnblock)
            : String(localizable: .chatContactsBlock)
    }
}

// MARK: - Additional addresses

private extension ChatContactFormView {
    /// Android's `WalletAddressesSection`: collapsed by default, three typed fields, each with
    /// its own scan icon that routes the result back to that field.
    var additionalAddresses: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            Button {
                store.send(.additionalAddressesToggled)
            } label: {
                HStack(spacing: Design.Spacing._xs) {
                    ZappSectionLabel(text: String(localizable: .chatContactsAdditionalAddresses))

                    Spacer()

                    (store.showsAdditionalAddresses
                        ? Asset.Assets.chevronUp.image
                        : Asset.Assets.chevronDown.image)
                        .zImage(
                            width: Constants.disclosureIconSize,
                            height: Constants.disclosureIconSize,
                            style: ZappColors.textMuted
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.zappPress)

            if store.showsAdditionalAddresses {
                typedAddressField(
                    label: String(localizable: .chatContactsAddrTransparent),
                    placeholder: String(localizable: .chatContactsAddrTransparentHint),
                    text: Binding(
                        get: { store.transparentAddress },
                        set: { store.send(.transparentAddressChanged($0)) }
                    ),
                    target: .transparent
                )

                typedAddressField(
                    label: String(localizable: .chatContactsAddrEvm),
                    placeholder: String(localizable: .chatContactsAddrEvmHint),
                    text: Binding(
                        get: { store.evmAddress },
                        set: { store.send(.evmAddressChanged($0)) }
                    ),
                    target: .evm
                )

                typedAddressField(
                    label: String(localizable: .chatContactsAddrSolana),
                    placeholder: String(localizable: .chatContactsAddrSolanaHint),
                    text: Binding(
                        get: { store.solanaAddress },
                        set: { store.send(.solanaAddressChanged($0)) }
                    ),
                    target: .solana
                )
            }
        }
    }

    func typedAddressField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        target: ChatContactForm.ScanTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: label)

            HStack(spacing: 0) {
                TextField(placeholder, text: text, axis: .vertical)
                    .zappFont(.mono, style: ZappColors.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2, reservesSpace: true)
                    .padding(Design.Spacing._md)

                scanButton(target: target, accessibilityLabel: String(localizable: .chatContactsScanAddress))
            }
            .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    func scanButton(target: ChatContactForm.ScanTarget, accessibilityLabel: String) -> some View {
        Button {
            store.send(.scanTapped(target))
        } label: {
            Asset.Assets.Icons.scan.image
                .zImage(width: Constants.scanIconSize, height: Constants.scanIconSize, style: ZappColors.textMuted)
                .frame(width: Constants.closeTouchTarget, height: Constants.closeTouchTarget)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ChatContactFormView(
        store: StoreOf<ChatContactForm>(initialState: ChatContactForm.State()) {
            ChatContactForm()
        }
    )
}
