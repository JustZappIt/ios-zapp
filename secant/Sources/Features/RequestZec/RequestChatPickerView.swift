//
//  RequestChatPickerView.swift
//  Zapp
//
//  The "Send request to" sheet — Android's `ChatContactPickerSheet` in `RequestQrCodeView.kt`:
//  a spinner while sending, "No chat contacts yet" when there is nobody to pick, else the list.
//

import ComposableArchitecture
import SwiftUI

struct RequestChatPickerView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let iconSize: CGFloat = 20
        static let rowHeight: CGFloat = 52
        /// Android caps the list at 360dp and scrolls past it.
        static let maxListHeight: CGFloat = 360
    }

    let store: StoreOf<RequestChatPicker>

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localizable: .requestZecSendInChatTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._lg)

                if store.isSending {
                    ProgressView()
                        .tint(ZappColors.accent.color(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Design.Spacing._3xl)
                } else if store.contacts.isEmpty {
                    Text(String(localizable: .requestZecSendInChatEmpty))
                        .zappFont(.body, style: ZappColors.textMuted)
                } else {
                    contactList
                }

                if store.didFail {
                    Text(String(localizable: .chatRoomSplitFailed))
                        .zappFont(.caption, style: ZappColors.danger)
                        .padding(.top, Design.Spacing._md)
                }
            }
            .padding(.bottom, Design.Spacing._3xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .interactiveDismissDisabled(store.isSending)
        }
    }

    // A fixed height, because the sheet sizes itself to its content and a bare ScrollView has none.
    private var contactList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.contacts) { contact in
                    row(contact)
                }
            }
        }
        .frame(height: min(CGFloat(store.contacts.count) * Constants.rowHeight, Constants.maxListHeight))
    }

    private func row(_ contact: ChatContact) -> some View {
        Button {
            store.send(.contactTapped(contact))
        } label: {
            HStack(spacing: Design.Spacing._xl) {
                Asset.Assets.Icons.messageChat.image
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accent)

                Text(contact.name)
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .lineLimit(1)

                Spacer()
            }
            .frame(height: Constants.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(contact.name)
    }
}
