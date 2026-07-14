//
//  NewChatView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct NewChatView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<NewChat>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .newChatTitle)) {
                    ZappBackButton { store.send(.backToHomeTapped) }
                } right: {
                    EmptyView()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                        searchField

                        if store.isValidKey {
                            keyDetectedBanner
                        }

                        if store.showsNameField {
                            nameField
                        }

                        startButton
                        contacts
                        myKeyCard
                    }
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    /// One field, two jobs: it filters the contacts below and detects a pasted key.
    private var searchField: some View {
        HStack(spacing: Design.Spacing._sm) {
            TextField(
                String(localizable: .newChatSearchPlaceholder),
                text: Binding(
                    get: { store.searchInput },
                    set: { store.send(.peerKeyChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                store.send(.pasteTapped)
            } label: {
                Text(String(localizable: .newChatPaste))
                    .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
            }
        }
        .padding(Design.Spacing._md)
        .background(ZappColors.surfaceInput.color(colorScheme))
    }

    private var keyDetectedBanner: some View {
        Button {
            store.send(.startTapped)
        } label: {
            HStack(spacing: Design.Spacing._sm) {
                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(String(localizable: .newChatKeyDetected))
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Text(store.detectedContact?.name ?? store.detectedKey)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .zImage(width: Constants.bannerIconSize, height: Constants.bannerIconSize, style: ZappColors.accent)
            }
            .padding(Design.Spacing._md)
            .frame(maxWidth: .infinity)
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatNameLabel))

            TextField(
                String(localizable: .newChatNamePlaceholder),
                text: Binding(
                    get: { store.displayName },
                    set: { store.send(.displayNameChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappButton(
                title: String(localizable: .newChatStart),
                isEnabled: store.canStart
            ) {
                store.send(.startTapped)
            }
            .frame(maxWidth: .infinity)

            if store.errorCode != nil {
                Text(String(localizable: .newChatFailed))
                    .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
            }
        }
    }

    @ViewBuilder private var contacts: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatContactsLabel))

            if store.visibleContacts.isEmpty {
                Text(String(localizable: .newChatNoContacts))
                    .zappFont(.body, style: ZappColors.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.filteredContacts) { contact in
                        NewChatContactRow(contact: contact) {
                            store.send(.contactTapped(contact))
                        }

                        if contact.id != store.filteredContacts.last?.id {
                            rowDivider
                        }
                    }
                }
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(height: 1)
            .padding(.leading, NewChatContactRow.dividerInset)
    }

    /// Chat is symmetric: the peer needs our key just as much as we need theirs.
    /// Without this the screen only works for whoever was handed a key first.
    private var myKeyCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatYourKey))

            Text(store.myPublicKey)
                .zappFont(.mono, color: ZappColors.text.color(colorScheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing._md)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            HStack {
                Text(String(localizable: .newChatYourKeyHint))
                    .zappFont(.caption, color: ZappColors.textMuted.color(colorScheme))

                Spacer()

                Button {
                    store.send(.copyMyKeyTapped)
                } label: {
                    Text(
                        store.didCopy
                            ? String(localizable: .newChatCopied)
                            : String(localizable: .newChatCopy)
                    )
                    .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
                }
            }
        }
        .padding(.top, Design.Spacing._lg)
    }

    private enum Constants {
        static let bannerIconSize: CGFloat = 16
    }
}

private struct NewChatContactRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 40
        static let avatarIconSize: CGFloat = 18
        static let spacing: CGFloat = 12
        static let verticalPadding: CGFloat = 10
    }

    static let dividerInset: CGFloat = Constants.avatarSize + Constants.spacing

    let contact: ChatContact
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.spacing) {
                avatar

                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(contact.name)
                        .zappFont(.rowTitle, style: ZappColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(contact.publicKey)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    private var avatar: some View {
        ZStack {
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.avatarIconSize, height: Constants.avatarIconSize)
                    .zForegroundColor(ZappColors.onAccent)
            } else {
                Text(initials)
                    .zappFont(.rowTitle, style: ZappColors.onAccent)
            }
        }
        .frame(width: Constants.avatarSize, height: Constants.avatarSize)
        .background(ZappColors.accent.color(colorScheme))
    }

    private var initials: String {
        contact.name.zappInitials.trimmingCharacters(in: .whitespaces)
    }
}
