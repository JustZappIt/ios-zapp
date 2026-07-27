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
                    groupModeToggle
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                        searchField

                        if !store.selectedContacts.isEmpty {
                            selectedParticipants
                        }

                        if store.isValidKey && !store.isOwnKey {
                            keyDetectedBanner
                        }

                        if store.isOwnKey {
                            Text(String(localizable: .newChatOwnKey))
                                .zappFont(.caption, style: ZappColors.danger)
                        }

                        if store.showsNameField {
                            nameField
                        }

                        if store.isNamingGroup {
                            groupNameField
                        }

                        primaryAction
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
            .zappSwipeBack { store.send(.backToHomeTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .fullScreenCover(item: $store.scope(state: \.scan, action: \.scan)) { scanStore in
                WithPerceptionTracking {
                    ScanView(store: scanStore)
                }
            }
        }
    }

    private var groupModeToggle: some View {
        Button {
            store.send(store.isGroupMode ? .groupCancelTapped : .newGroupTapped)
        } label: {
            Text(
                store.isGroupMode
                    ? String(localizable: .generalCancel)
                    : String(localizable: .groupNewGroup)
            )
            .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
        }
        .disabled(store.isCreating)
    }

    private var selectedParticipants: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing._sm) {
                ForEach(store.selectedContacts) { contact in
                    NewChatParticipantChip(name: contact.name) {
                        store.send(.participantRemoved(contact.publicKey))
                    }
                }
            }
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

            Button {
                store.send(.scanTapped)
            } label: {
                Asset.Assets.Icons.scan.image
                    .zImage(width: Constants.scanIconSize, height: Constants.scanIconSize, style: ZappColors.accent)
                    .frame(width: Constants.scanTouchTarget, height: Constants.scanTouchTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .chatContactsScanKey))
        }
        .padding(.leading, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._md)
        .background(ZappColors.surfaceInput.color(colorScheme))
    }

    /// In group mode the same banner adds the pasted key as a participant instead of opening a DM.
    @ViewBuilder private var keyDetectedBanner: some View {
        if !store.isDetectedKeySelected {
            Button {
                store.send(store.isGroupMode ? .detectedKeyAdded : .startTapped)
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

                    (store.isGroupMode ? Asset.Assets.Icons.plus : Asset.Assets.Icons.arrowRight).image
                        .zImage(
                            width: Constants.bannerIconSize,
                            height: Constants.bannerIconSize,
                            style: ZappColors.accent
                        )
                }
                .padding(Design.Spacing._md)
                .frame(maxWidth: .infinity)
                .background(ZappColors.surfaceAlt.color(colorScheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(.zappPress)
        }
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

    private var groupNameField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .groupName))

            TextField(
                String(localizable: .groupNamePlaceholder),
                text: Binding(
                    get: { store.groupName },
                    set: { store.send(.groupNameChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .autocorrectionDisabled()
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    @ViewBuilder private var primaryAction: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            if store.isGroupMode {
                if !store.selectedContacts.isEmpty {
                    ZappButton(
                        title: String(localizable: .groupCreate),
                        isEnabled: store.isNamingGroup ? store.canConfirmGroup : store.canCreateGroup
                    ) {
                        store.send(store.isNamingGroup ? .groupConfirmTapped : .groupCreateTapped)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ZappButton(
                    title: String(localizable: .newChatStart),
                    isEnabled: store.canStart
                ) {
                    store.send(.startTapped)
                }
                .frame(maxWidth: .infinity)
            }

            if store.errorCode != nil && store.errorCode != .ownPublicKey {
                Text(String(localizable: .newChatFailed))
                    .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
            }
        }
    }
}

// MARK: - Contact list & own key

private extension NewChatView {
    @ViewBuilder var contacts: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(
                text: store.isGroupMode
                    ? String(localizable: .groupSelectMembers)
                    : String(localizable: .newChatContactsLabel)
            )

            if store.visibleContacts.isEmpty {
                Text(String(localizable: .newChatNoContacts))
                    .zappFont(.body, style: ZappColors.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.filteredContacts) { contact in
                        NewChatContactRow(
                            contact: contact,
                            isSelectable: store.isGroupMode,
                            isSelected: store.state.isSelected(contact)
                        ) {
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

    var rowDivider: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(height: 1)
            .padding(.leading, NewChatContactRow.dividerInset)
    }

    /// Chat is symmetric: the peer needs our key just as much as we need theirs.
    /// Without this the screen only works for whoever was handed a key first.
    var myKeyCard: some View {
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
        static let scanIconSize: CGFloat = 20
        static let scanTouchTarget: CGFloat = 44
    }
}

private struct NewChatParticipantChip: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let iconSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let spacing: CGFloat = 6
    }

    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.spacing) {
                Text(name)
                    .zappFont(.chip, style: ZappColors.accentText)
                    .lineLimit(1)

                Asset.Assets.Icons.xClose.image
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accentText)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .background(ZappColors.accentSoft.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(name)
    }
}

private struct NewChatContactRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 40
        static let avatarIconSize: CGFloat = 18
        static let spacing: CGFloat = 12
        static let verticalPadding: CGFloat = 10
        static let checkboxSize: CGFloat = 20
        static let checkIconSize: CGFloat = 11
    }

    static let dividerInset: CGFloat = Constants.avatarSize + Constants.spacing

    let contact: ChatContact
    var isSelectable = false
    var isSelected = false
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

                if isSelectable {
                    selectionBox
                }
            }
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    private var selectionBox: some View {
        ZStack {
            if isSelected {
                Asset.Assets.check.image
                    .zImage(width: Constants.checkIconSize, height: Constants.checkIconSize, style: ZappColors.onAccent)
            }
        }
        .frame(width: Constants.checkboxSize, height: Constants.checkboxSize)
        .background((isSelected ? ZappColors.accent : ZappColors.surfaceInput).color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder((isSelected ? ZappColors.accent : ZappColors.borderStrong).color(colorScheme), lineWidth: 1)
        }
    }

    private var avatar: some View {
        ZStack {
            if initials.isEmpty {
                Asset.Assets.Icons.user.image
                    .zImage(width: Constants.avatarIconSize, height: Constants.avatarIconSize, style: ZappColors.onAccent)
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
