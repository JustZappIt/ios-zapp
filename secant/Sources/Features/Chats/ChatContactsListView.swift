//
//  ChatContactsListView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ChatContactsListView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let sectionInset: CGFloat = 18
        static let sectionTop: CGFloat = 14
        static let emptyIconSize: CGFloat = 56
    }

    @Perception.Bindable var store: StoreOf<ChatContactsList>

    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    ZappScreenHeader(title: String(localizable: .chatContactsTitle)) {
                        ZappStatusChip(text: String(localizable: .chatContactsSavedCount(store.contacts.count)))
                    }

                    if store.contacts.isEmpty {
                        emptyState
                    } else {
                        contacts
                    }
                }

                ZappFab(
                    icon: Asset.Assets.Icons.userPlus.image,
                    accessibilityLabel: String(localizable: .chatContactsAdd)
                ) {
                    store.send(.addTapped)
                }
                .padding(.trailing, Design.Spacing._2xl)
                .padding(.bottom, Design.Spacing._lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ZappBottomActionBar(onBack: { store.send(.backToHomeTapped) })
            }
            .zappSwipeBack(isEnabled: store.form == nil) { store.send(.backToHomeTapped) }
            .onAppear { store.send(.onAppear) }
            .sheet(item: $store.scope(state: \.form, action: \.form)) { formStore in
                // A sheet's content closure escapes: reads inside it only register with TCA's
                // observation system under their own WithPerceptionTracking.
                WithPerceptionTracking {
                    ChatContactFormView(store: formStore)
                }
            }
        }
    }

    private var contacts: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.sections) { section in
                    ZappSectionLabel(text: section.letter)
                        .padding(.horizontal, Constants.sectionInset)
                        .padding(.top, Constants.sectionTop)
                        .padding(.bottom, Design.Spacing._xs)

                    ForEach(section.contacts) { contact in
                        ChatContactRow(
                            contact: contact,
                            onEdit: { store.send(.contactTapped(contact)) },
                            onStartChat: { store.send(.startChatTapped(contact)) }
                        )

                        if contact.id != section.contacts.last?.id {
                            ZappRowDivider(inset: true)
                        }
                    }
                }
            }
            .padding(.top, Design.Spacing._xs)
            .padding(.bottom, ZappNavBar.pushedFloatingMargin)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Asset.Assets.Icons.users.image
                .zImage(width: Constants.emptyIconSize, height: Constants.emptyIconSize, style: ZappColors.textSubtle)
                .padding(.bottom, Design.Spacing._lg)

            Text(String(localizable: .chatContactsEmptyTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.bottom, Design.Spacing._sm)

            Text(String(localizable: .chatContactsEmptySubtitle))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Design.Spacing._4xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ChatContactRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 12
        static let spacing: CGFloat = 12
        static let chatIconSize: CGFloat = 22
        static let touchTarget: CGFloat = 48
    }

    let contact: ChatContact
    let onEdit: () -> Void
    let onStartChat: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onEdit) { row }
                .buttonStyle(.zappPress)

            // Android hides Start chat for a blocked contact; unblocking goes through the edit sheet.
            if !contact.isBlocked {
                Button(action: onStartChat) {
                    Asset.Assets.Icons.messageChat.image
                        .zImage(width: Constants.chatIconSize, height: Constants.chatIconSize, style: ZappColors.accent)
                        .frame(width: Constants.touchTarget, height: Constants.touchTarget)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .chatContactsStartChat))
                .padding(.trailing, Constants.horizontalPadding - Design.Spacing._md)
            }
        }
    }

    private var row: some View {
        HStack(spacing: Constants.spacing) {
            Text(contact.name.zappInitials)
                .zappFont(.rowTitle, style: ZappColors.onAccent)
                .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                .background(ZappColors.accent.color(colorScheme))

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(contact.name)
                    .zappFont(.rowTitle, style: contact.isBlocked ? ZappColors.textMuted : ZappColors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Blocked replaces the key rather than sitting beside it, as on Android.
                if contact.isBlocked {
                    Text(String(localizable: .chatContactsBlocked))
                        .zappFont(.caption, style: ZappColors.danger)
                } else {
                    Text(contact.publicKey.zappEllipsized())
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Constants.horizontalPadding)
        .padding(.trailing, contact.isBlocked ? Constants.horizontalPadding : 0)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#Preview {
    ChatContactsListView(
        store: StoreOf<ChatContactsList>(initialState: .initial) {
            ChatContactsList()
        }
    )
}
