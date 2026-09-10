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
        static let validKeyIconSize: CGFloat = 14
        static let keyHeadLength = 10
        static let keyTailLength = 6
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
            .sheet(item: $store.scope(state: \.scan, action: \.scan)) { scanStore in
                ScanView(store: scanStore)
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
        ZappInputField(
            placeholder: String(localizable: .chatContactsNamePlaceholder),
            text: Binding(
                get: { store.name },
                set: { store.send(.nameChanged($0)) }
            ),
            accessibilityLabel: String(localizable: .chatContactsNameLabel)
        ) {
            ZappInputFieldGlyph(icon: Asset.Assets.Icons.user.image)
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            if store.isKeyLocked {
                Text(store.publicKey)
                    .zappFont(.mono, style: ZappColors.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._md)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
            } else {
                ZappInputField(
                    placeholder: String(localizable: .newChatPeerPlaceholder),
                    text: Binding(
                        get: { store.publicKey },
                        set: { store.send(.publicKeyChanged($0)) }
                    ),
                    isVerbatim: true,
                    accessibilityLabel: String(localizable: .chatContactsKeyLabel),
                    leading: { ZappInputFieldGlyph(icon: Asset.Assets.Icons.key.image) },
                    trailing: {
                        ZappInputFieldAction(
                            icon: Asset.Assets.Icons.scan.image,
                            accessibilityLabel: String(localizable: .chatContactsScanKey)
                        ) {
                            store.send(.scanTapped(.publicKey))
                        }
                    }
                )

                if store.isValidKey {
                    validKeyRow
                }
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
            ZappInputField(
                placeholder: String(localizable: .chatContactsAddressPlaceholder),
                text: Binding(
                    get: { store.address },
                    set: { store.send(.addressChanged($0)) }
                ),
                isVerbatim: true,
                accessibilityLabel: String(localizable: .chatContactsAddressLabel),
                leading: { ZappInputFieldGlyph(icon: Asset.Assets.Icons.connectWallet.image) },
                trailing: {
                    ZappInputFieldAction(
                        icon: Asset.Assets.Icons.scan.image,
                        accessibilityLabel: String(localizable: .chatContactsScanAddress)
                    ) {
                        store.send(.scanTapped(.address))
                    }
                }
            )

            if !store.isValidAddress {
                Text(String(localizable: .chatContactsInvalidAddress))
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    /// Android confirms a good key in place rather than only rejecting a bad one
    /// (`AddChatContactSheet.kt:143-168`): the key, abbreviated, on a soft success ground.
    private var validKeyRow: some View {
        HStack(spacing: Design.Spacing._md) {
            Asset.Assets.Icons.checkVerified.image
                .zImage(
                    width: Constants.validKeyIconSize,
                    height: Constants.validKeyIconSize,
                    style: ZappColors.success
                )

            Text(abbreviatedKey)
                .zappFont(.chip, style: ZappColors.success)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing._lg)
        .padding(.vertical, Design.Spacing._md)
        .frame(maxWidth: .infinity)
        .background(ZappColors.successSoft.color(colorScheme))
    }

    private var abbreviatedKey: String {
        let key = store.publicKey
        guard key.count > Constants.keyHeadLength + Constants.keyTailLength else { return key }
        return "\(key.prefix(Constants.keyHeadLength))…\(key.suffix(Constants.keyTailLength))"
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
