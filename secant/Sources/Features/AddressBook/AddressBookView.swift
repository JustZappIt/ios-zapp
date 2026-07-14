//
//  AddressBookView.swift
//  Zashi
//
//  Created by Lukáš Korba on 05-28-2024.
//

import SwiftUI
import ComposableArchitecture

/// The ZEC address book. Chat contacts are a separate screen (`ChatContactsListView`) with a separate
/// store; the two are never merged.
struct AddressBookView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let emptyIconSize: CGFloat = 32
        static let emptyIconBoxSize: CGFloat = 72
        static let menuIconSize: CGFloat = 20
    }

    @Perception.Bindable var store: StoreOf<AddressBook>

    init(store: StoreOf<AddressBook>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                if store.isInSelectMode && store.walletAccounts.count > 1 && store.context != .swap {
                    contactsList()
                } else if store.addressBookContactsToShow.contacts.isEmpty {
                    Spacer()

                    emptyState()

                    Spacer()
                } else {
                    contactsList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Design.Spacing._3xl)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .zashiBack(primaryAction: { addContactButton })
            .screenTitle(
                store.isInSelectMode
                && (!store.addressBookContactsToShow.contacts.isEmpty || store.walletAccounts.count > 1 || store.context == .swap)
                ? String(localizable: .addressBookSelectRecipient)
                : String(localizable: .addressBookTitle)
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var addContactButton: some View {
        WithPerceptionTracking {
            Menu {
                Button {
                    store.send(.scanButtonTapped)
                } label: {
                    HStack {
                        Asset.Assets.Icons.qr.image
                            .zImage(size: Constants.menuIconSize, style: ZappColors.text)

                        Text(localizable: .addressBookScanAddress)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.AddressBook.scanEntry)

                Button {
                    store.send(.addManualButtonTapped)
                } label: {
                    HStack {
                        Asset.Assets.Icons.pencil.image
                            .zImage(size: Constants.menuIconSize, style: ZappColors.text)

                        Text(localizable: .addressBookManualEntry)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.AddressBook.manualEntry)
            } label: {
                // The Menu owns the tap; the button is a label, so its own action stays empty, as upstream.
                ZappButton(
                    title: String(localizable: .addressBookAddNewContact),
                    leadingIcon: Asset.Assets.Icons.plus.image
                ) { }
            }
            .accessibilityIdentifier(AccessibilityID.AddressBook.addContact)
        }
    }

    private func emptyState() -> some View {
        VStack(spacing: Design.Spacing._5xl) {
            Asset.Assets.send.image
                .zImage(size: Constants.emptyIconSize, style: ZappColors.textSubtle)
                .frame(width: Constants.emptyIconBoxSize, height: Constants.emptyIconBoxSize)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            Text(localizable: .addressBookEmpty)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Design.Spacing._lg)
    }

    @ViewBuilder private func contactsList() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.walletAccounts.count > 1 && store.isInSelectMode && store.context != .swap {
                    ZappGroupHeader(text: String(localizable: .accountsAddressBookYour))

                    VStack(spacing: 0) {
                        ForEach(store.walletAccounts, id: \.self) { walletAccount in
                            WithPerceptionTracking {
                                if walletAccount != store.selectedWalletAccount {
                                    AddressBookRow(
                                        title: walletAccount.vendor.name(),
                                        subtitle: (
                                            walletAccount.unifiedAddress
                                            ?? String(localizable: .receiveErrorCantExtractUnifiedAddress)
                                        ).zip316,
                                        leading: .vendor(walletAccount.vendor.icon())
                                    ) {
                                        store.send(.walletAccountTapped(walletAccount))
                                    }

                                    if store.walletAccounts.last != walletAccount {
                                        ZappRowDivider(inset: true)
                                    }
                                }
                            }
                        }
                    }
                    .zappCard()

                    if store.addressBookContactsToShow.contacts.isEmpty {
                        emptyState()
                            .padding(.top, Design.Spacing._7xl)
                            .padding(.bottom, Design.Spacing._5xl)
                    } else {
                        ZappGroupHeader(text: String(localizable: .accountsAddressBookContacts))
                    }
                }

                if !store.addressBookContactsToShow.contacts.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(store.addressBookContactsToShow.contacts, id: \.self) { record in
                            WithPerceptionTracking {
                                AddressBookRow(
                                    title: record.name,
                                    subtitle: record.address.trailingZip316,
                                    leading: .initials(
                                        record.name.zappInitials,
                                        ticker: AddressBook.contactTicker(chainId: record.chainId)
                                    )
                                ) {
                                    store.send(.editId(record.address, record.id))
                                }

                                if store.addressBookContactsToShow.contacts.last != record {
                                    ZappRowDivider(inset: true)
                                }
                            }
                        }
                    }
                    .zappCard()
                }
            }
            .padding(.bottom, ZappNavBar.pushedFloatingMargin)
        }
    }
}

/// A `ZappRow`-shaped row whose leading slot is either an initials tile or a vendor mark. `ZappRow`
/// only takes a template `Image`, which would flatten a vendor logo to a single tint.
private struct AddressBookRow: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Leading {
        case initials(String, ticker: Image?)
        case vendor(Image)
    }

    private enum Constants {
        static let minHeight: CGFloat = 56
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 12
        static let spacing: CGFloat = 14
        static let tileSize: CGFloat = 36
        static let vendorIconSize: CGFloat = 20
        static let tickerSize: CGFloat = 14
        static let chevronSize: CGFloat = 18
    }

    let title: String
    let subtitle: String
    let leading: Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.spacing) {
                leadingTile

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .zappFont(.rowTitle, style: ZappColors.text)
                        .lineLimit(1)

                    Text(subtitle)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Asset.Assets.chevronRight.image
                    .zImage(size: Constants.chevronSize, style: ZappColors.textSubtle)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    @ViewBuilder private var leadingTile: some View {
        switch leading {
        case let .initials(initials, ticker):
            Text(initials)
                .zappFont(.caption, style: ZappColors.accentText)
                .minimumScaleFactor(0.5)
                .frame(width: Constants.tileSize, height: Constants.tileSize)
                .background(ZappColors.accentSoft.color(colorScheme))
                .overlay(alignment: .bottomTrailing) {
                    if let ticker {
                        ticker
                            .resizable()
                            .frame(width: Constants.tickerSize, height: Constants.tickerSize)
                            .padding(1)
                            .background(ZappColors.surface.color(colorScheme))
                    }
                }
        case let .vendor(icon):
            icon
                .resizable()
                .frame(width: Constants.vendorIconSize, height: Constants.vendorIconSize)
                .frame(width: Constants.tileSize, height: Constants.tileSize)
                .background(ZappColors.surfaceAlt.color(colorScheme))
        }
    }
}

private struct ZappCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, Design.Spacing._lg)
    }
}

private extension View {
    func zappCard() -> some View {
        modifier(ZappCard())
    }
}

// MARK: - Previews

#Preview {
    AddressBookView(store: AddressBook.initial)
}

// MARK: - Store

extension AddressBook {
    @MainActor static var initial = StoreOf<AddressBook>(
        initialState: .initial
    ) {
        AddressBook()
    }
}

// MARK: - Placeholders

extension AddressBook.State {
    static var initial: AddressBook.State { AddressBook.State() }
}
