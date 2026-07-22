//
//  ChatContactsListView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ChatContactsListView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatContactsList>

    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    ZappScreenHeader(title: String(localizable: .chatContactsTitle)) {
                        ZappBackButton { store.send(.backToHomeTapped) }
                    } right: {
                        EmptyView()
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
                .padding(.bottom, ZappNavBar.pushedFloatingMargin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack { store.send(.backToHomeTapped) }
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
            LazyVStack(spacing: 0) {
                ForEach(store.contacts) { contact in
                    ChatContactRow(contact: contact) {
                        store.send(.contactTapped(contact))
                    }

                    if contact.id != store.contacts.last?.id {
                        ZappRowDivider(inset: true)
                    }
                }
            }
            .padding(.top, Design.Spacing._xs)
            .padding(.bottom, ZappNavBar.pushedFloatingMargin)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing._sm) {
            Text(String(localizable: .chatContactsEmptyTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

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
    }

    let contact: ChatContact
    let action: () -> Void

    var body: some View {
        Button(action: action) { row }
            .buttonStyle(.zappPress)
    }

    private var row: some View {
        HStack(spacing: Constants.spacing) {
            Text(contact.name.zappInitials)
                .zappFont(.rowTitle, style: ZappColors.onAccent)
                .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                .background(ZappColors.accent.color(colorScheme))

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(contact.name)
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(contact.publicKey.zappEllipsized())
                    .zappFont(.mono, style: ZappColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if contact.isBlocked {
                ZappStatusChip(text: String(localizable: .chatContactsBlocked), variant: .danger)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
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
