//
//  AddressBookContactView.swift
//  Zashi
//
//  Created by Lukáš Korba on 05-28-2024.
//

import SwiftUI
import ComposableArchitecture

struct AddressBookContactView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let chainIconSize: CGFloat = 24
        static let chevronSize: CGFloat = 18
    }

    @Perception.Bindable var store: StoreOf<AddressBook>

    @FocusState var isAddressFocused: Bool
    @FocusState var isNameFocused: Bool
    @FocusState var isChainIdFocused: Bool

    init(store: StoreOf<AddressBook>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                    field(
                        title: String(localizable: .addressBookNewContactAddress),
                        placeholder: String(localizable: .addressBookNewContactAddressPlaceholder),
                        text: $store.address,
                        error: store.invalidAddressErrorText,
                        isMono: true
                    )
                    .focused($isAddressFocused)
                    .accessibilityIdentifier(AccessibilityID.AddressBookContact.walletAddressField)

                    field(
                        title: String(localizable: .addressBookNewContactName),
                        placeholder: String(localizable: .addressBookNewContactNamePlaceholder),
                        text: $store.name,
                        error: store.invalidNameErrorText,
                        isMono: false
                    )
                    .focused($isNameFocused)
                    .accessibilityIdentifier(AccessibilityID.AddressBookContact.contactNameField)

                    if store.context != .send || store.isEditingContactWithChain {
                        if store.isValidZcashAddress && store.context != .swap {
                            lockedChain
                        } else {
                            chainSelector
                                .focused($isChainIdFocused)
                        }
                    }

                    if store.editId != nil {
                        ZappButton(title: String(localizable: .generalDelete), variant: .danger) {
                            store.send(.deleteId(store.uniqueId))
                        }
                        .accessibilityIdentifier(AccessibilityID.AddressBookContact.deleteButton)
                    }
                }
                .padding(.horizontal, Design.Spacing._lg)
                .padding(.top, Design.Spacing._2xl)
                .padding(.bottom, ZappNavBar.pushedFloatingMargin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear {
                isAddressFocused = store.isAddressFocused
                if !isAddressFocused {
                    isNameFocused = store.isNameFocused
                }
                store.send(.onAppear)
            }
            .alert(
                store: store.scope(
                    state: \.$alert,
                    action: \.alert
                )
            )
            .popover(isPresented: $store.chainSelectBinding) {
                assetContent(colorScheme)
                    .padding(.horizontal, Design.Spacing._xs)
                    .background(ZappColors.bg.color(colorScheme))
            }
            .zashiBack(primaryAction: { saveButton })
            .screenTitle(
                store.editId != nil
                ? String(localizable: .addressBookSavedAddress)
                : String(localizable: .swapAndPayAddressBookNewContact)
            )
        }
    }

    private var saveButton: some View {
        WithPerceptionTracking {
            ZappButton(
                title: String(localizable: .generalSave),
                isEnabled: !store.isSaveButtonDisabled
            ) {
                store.send(.saveButtonTapped)
            }
            .accessibilityIdentifier(AccessibilityID.AddressBookContact.saveButton)
        }
    }

    @ViewBuilder private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        error: String?,
        isMono: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: title)

            TextField(placeholder, text: text, axis: .vertical)
                .zappFont(isMono ? .mono : .body, style: ZappColors.text)
                .textInputAutocapitalization(isMono ? .never : .words)
                .autocorrectionDisabled()
                .lineLimit(isMono ? 2 : 1, reservesSpace: true)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceInput.color(colorScheme))

            if let error {
                Text(error)
                    .zappFont(.caption, style: ZappColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lockedChain: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .swapAndPayAddressBookSelectChain))

            HStack(spacing: Design.Spacing._md) {
                store.zecAsset.chainIcon
                    .resizable()
                    .frame(width: Constants.chainIconSize, height: Constants.chainIconSize)

                Text(store.zecAsset.chainName)
                    .zappFont(.body, style: ZappColors.textMuted)

                Spacer()

                Asset.Assets.chevronDown.image
                    .zImage(size: Constants.chevronSize, style: ZappColors.textSubtle)
            }
            .padding(Design.Spacing._lg)
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
        }
    }

    private var chainSelector: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .swapAndPayAddressBookSelectChain))

            Button {
                store.send(.selectChainTapped)
            } label: {
                HStack(spacing: Design.Spacing._md) {
                    if let selectedChain = store.selectedChain {
                        selectedChain.chainIcon
                            .resizable()
                            .frame(width: Constants.chainIconSize, height: Constants.chainIconSize)

                        Text(selectedChain.chainName)
                            .zappFont(.body, style: ZappColors.text)
                    } else {
                        Text(localizable: .swapAndPayAddressBookSelect)
                            .zappFont(.body, style: ZappColors.textSubtle)
                    }

                    Spacer()

                    Asset.Assets.chevronDown.image
                        .zImage(size: Constants.chevronSize, style: ZappColors.text)
                }
                .padding(Design.Spacing._lg)
                .frame(maxWidth: .infinity)
                .background(ZappColors.surfaceInput.color(colorScheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(.zappPress)
            .accessibilityIdentifier(AccessibilityID.AddressBookContact.chainSelector)
        }
    }
}

#Preview {
    AddressBookContactView(store: AddressBook.initial)
}
