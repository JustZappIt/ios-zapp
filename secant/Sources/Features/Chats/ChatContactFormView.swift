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
    }

    @Perception.Bindable var store: StoreOf<ChatContactForm>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: title)

                ScrollView {
                    VStack(spacing: 0) {
                        contactPreview
                            .padding(.horizontal, 14)
                            .padding(.top, Design.Spacing._lg)

                        ZappSettingsGroup(title: String(localizable: .chatContactsFormDetails)) {
                            VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                                labeledField(String(localizable: .chatContactsNameLabel)) { nameField }
                                labeledField(String(localizable: .chatContactsKeyLabel)) { keyField }
                            }
                            .padding(Design.Spacing._lg)
                        }

                        ZappSettingsGroup(title: String(localizable: .chatContactsFormPayments)) {
                            VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                                Text(localizable: .chatContactsFormPaymentsHint)
                                    .zappFont(.caption, style: ZappColors.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                labeledField(String(localizable: .chatContactsAddressLabel)) { addressField }
                            }
                            .padding(Design.Spacing._lg)
                        }

                        if store.isBlocked {
                            Text(String(localizable: .chatContactsBlockedNotice))
                                .zappFont(.caption, style: ZappColors.danger)
                                .padding(Design.Spacing._lg)
                        }

                        if store.canBlock || store.isEditing {
                            buttons
                                .padding(.horizontal, 14)
                                .padding(.top, Design.Spacing._md)
                        }
                    }
                    .padding(.bottom, Design.Spacing._lg)
                }
                .scrollDismissesKeyboard(.interactively)

                ZappBottomActionBar(onBack: { store.send(.closeTapped) }) {
                    ZappButton(title: String(localizable: .chatContactsSave), isEnabled: store.canSave) {
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

    private var contactPreview: some View {
        ZappRow(
            title: store.trimmedName.isEmpty ? String(localizable: .chatContactsFormPreview) : store.trimmedName,
            subtitle: store.isValidKey ? abbreviatedKey : String(localizable: .chatContactsFormIntro),
            icon: Asset.Assets.Icons.user.image,
            iconTint: .accentText,
            iconBackground: .accentSoft,
            trailing: { EmptyView() }
        )
        .background(ZappColors.surface.color(colorScheme))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: 3)
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._sm) {
            ZappSectionLabel(text: label)
            content()
        }
    }

    private var title: String {
        store.isEditing
            ? String(localizable: .chatContactsEdit)
            : String(localizable: .chatContactsAdd)
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

#Preview {
    ChatContactFormView(
        store: StoreOf<ChatContactForm>(initialState: ChatContactForm.State()) {
            ChatContactForm()
        }
    )
}
