//
//  ChatContactFormView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ChatContactFormView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let validKeyIconSize: CGFloat = 14
        static let keyHeadLength = 10
        static let keyTailLength = 6
        static let screenInset: CGFloat = 18
        static let fieldSpacing: CGFloat = 12
        static let fieldInset: CGFloat = 14
        static let fieldHeight: CGFloat = 52
        static let glyphGap: CGFloat = 10
        static let confirmVerticalPadding: CGFloat = 14
    }

    @Perception.Bindable var store: StoreOf<ChatContactForm>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: title)

                // Android's compact sheet: three icon-led fields, one error line, then the actions.
                ScrollView {
                    VStack(alignment: .leading, spacing: Constants.fieldSpacing) {
                        nameField
                        keyField
                        addressField

                        if let errorMessage = store.errorMessage {
                            Text(errorMessage)
                                .zappFont(.caption, style: ZappColors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if store.isBlocked {
                            Text(String(localizable: .chatContactsBlockedNotice))
                                .zappFont(.caption, style: ZappColors.danger)
                        }

                        if store.isConfirmingDelete {
                            deleteConfirmation
                                .padding(.top, Design.Spacing._md)
                        } else if store.canBlock || store.isEditing {
                            buttons
                                .padding(.top, Design.Spacing._md)
                        }
                    }
                    .padding(.horizontal, Constants.screenInset)
                    .padding(.vertical, Design.Spacing._xl)
                }
                .scrollDismissesKeyboard(.interactively)

                ZappBottomActionBar(onBack: { store.send(.closeTapped) }) {
                    ZappButton(title: saveTitle, isEnabled: store.canSave) {
                        store.send(.saveTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack(isEnabled: store.scan == nil && store.alert == nil) { store.send(.closeTapped) }
            .onAppear { store.send(.onAppear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .sheet(item: $store.scope(state: \.scan, action: \.scan)) { scanStore in
                ScanView(store: scanStore)
            }
        }
    }

    /// Add vs Edit follows whether a row exists, so a peer opened from their conversation who is
    /// not saved yet reads as an add (Android always says "Edit Contact" there).
    private var title: String {
        store.isEditing
            ? String(localizable: .chatContactsEditTitle)
            : String(localizable: .chatContactsAddTitle)
    }

    private var saveTitle: String {
        store.isEditing
            ? String(localizable: .chatContactsSaveChanges)
            : String(localizable: .chatContactsSave)
    }

    /// Android offers copy wherever the contact is already known — its edit sheet.
    private var offersCopy: Bool { store.isKeyLocked }

    private func copyButton(_ field: ChatContactForm.CopyField, label: String) -> some View {
        ZappCopyIconButton(isCopied: store.copiedField == field, accessibilityLabel: label) {
            store.send(.copyTapped(field))
        }
    }

    /// A trailing slot, even an empty one, drops the field's right inset, so the copy button is
    /// either there for the whole edit (inert while the name is blank) or the slot is absent.
    @ViewBuilder private var nameField: some View {
        if offersCopy {
            ZappInputField(
                placeholder: String(localizable: .chatContactsNamePlaceholder),
                text: nameBinding,
                accessibilityLabel: String(localizable: .chatContactsNameLabel),
                leading: { ZappInputFieldGlyph(icon: Asset.Assets.Icons.user.image) },
                trailing: { copyButton(.name, label: String(localizable: .chatContactsCopyName)) }
            )
        } else {
            ZappInputField(
                placeholder: String(localizable: .chatContactsNamePlaceholder),
                text: nameBinding,
                accessibilityLabel: String(localizable: .chatContactsNameLabel)
            ) {
                ZappInputFieldGlyph(icon: Asset.Assets.Icons.user.image)
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.name },
            set: { store.send(.nameChanged($0)) }
        )
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            if store.isKeyLocked {
                lockedKeyRow
            } else {
                ZappInputField(
                    placeholder: String(localizable: .chatContactsKeyPlaceholder),
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
                    if offersCopy && !store.trimmedAddress.isEmpty {
                        copyButton(.address, label: String(localizable: .chatContactsCopyAddress))
                    }
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

    /// Android's read-only key row: the key abbreviated, in an input-shaped box, with copy.
    private var lockedKeyRow: some View {
        HStack(spacing: 0) {
            ZappInputFieldGlyph(icon: Asset.Assets.Icons.key.image)
                .padding(.trailing, Constants.glyphGap)

            Text(abbreviatedKey)
                .zappFont(.mono, style: ZappColors.textMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(String(localizable: .chatContactsKeyLabel))
                .accessibilityValue(store.publicKey)

            copyButton(.publicKey, label: String(localizable: .chatContactsCopyKey))
        }
        .padding(.leading, Constants.fieldInset)
        .frame(minHeight: Constants.fieldHeight)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay { Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1) }
    }

    private var buttons: some View {
        VStack(spacing: Design.Spacing._md) {
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

    /// Android's inline `DeleteConfirmation` panel, which stands in for the buttons until answered.
    private var deleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localizable: .chatContactsDeleteConfirmTitle))
                .zappFont(.rowTitle, style: ZappColors.danger)

            Text(String(localizable: .chatContactsDeleteConfirmSubtitle))
                .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                .padding(.top, Design.Spacing._xs)

            HStack(spacing: Design.Spacing._lg) {
                ZappButton(title: String(localizable: .generalCancel), variant: .secondary) {
                    store.send(.deleteCancelled)
                }
                .frame(maxWidth: .infinity)

                ZappButton(title: String(localizable: .chatContactsDeleteConfirm), variant: .danger) {
                    store.send(.deleteConfirmed)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, Design.Spacing._lg)
        }
        .padding(.horizontal, Design.Spacing._lg)
        .padding(.vertical, Constants.confirmVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.dangerSoft.color(colorScheme))
        .overlay { Rectangle().strokeBorder(ZappColors.danger.color(colorScheme), lineWidth: 1) }
    }

    private var blockTitle: String {
        store.isBlocked
            ? String(localizable: .chatContactsUnblock)
            : String(localizable: .chatContactsBlock)
    }
}

#Preview {
    ChatContactFormView(
        store: StoreOf<ChatContactForm>(initialState: ChatContactForm.State()) {
            ChatContactForm()
        }
    )
}
