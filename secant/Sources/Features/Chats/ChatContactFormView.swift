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
        static let scanIconSize: CGFloat = 16
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

    private var scanButton: some View {
        Button {
            store.send(.scanTapped)
        } label: {
            HStack(spacing: Design.Spacing._xs) {
                Asset.Assets.Icons.scan.image
                    .zImage(width: Constants.scanIconSize, height: Constants.scanIconSize, style: ZappColors.accent)

                Text(String(localizable: .newChatScan))
                    .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
            }
        }
        .buttonStyle(.zappPress)
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
            HStack(spacing: Design.Spacing._sm) {
                ZappSectionLabel(text: String(localizable: .chatContactsKeyLabel))

                Spacer(minLength: 0)

                if !store.isEditing {
                    scanButton
                }
            }

            if store.isEditing {
                Text(store.publicKey)
                    .zappFont(.mono, style: ZappColors.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._md)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
            } else {
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

            if store.isEditing {
                ZappButton(title: blockTitle, variant: .secondary) {
                    store.send(.blockTapped)
                }
                .frame(maxWidth: .infinity)

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
