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
                    groupModeToggle
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                        if store.showsRecipientCard {
                            recipientCard
                        } else {
                            searchField
                        }

                        if store.isOwnKey {
                            Text(String(localizable: .newChatOwnKey))
                                .zappFont(.caption, style: ZappColors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !store.selectedContacts.isEmpty {
                            selectedParticipants
                        }

                        if store.showsNameField {
                            nameField
                        }

                        if store.isNamingGroup {
                            groupNameField
                        }

                        if store.errorCode != nil && store.errorCode != .ownPublicKey {
                            Text(String(localizable: .newChatFailed))
                                .zappFont(.caption, style: ZappColors.danger)
                        }

                        if store.showsEmptyState {
                            emptyState
                        } else {
                            contacts
                        }

                        shareMyKeyRow
                    }
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, Design.Spacing._lg)
                }

                ZappBottomActionBar(
                    onBack: { store.send(.backToHomeTapped) },
                    isBackEnabled: !store.isCreating
                ) {
                    primaryButton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack { store.send(.backToHomeTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .sheet(item: $store.scope(state: \.scan, action: \.scan)) { scanStore in
                ScanView(store: scanStore)
            }
            .sheet(
                isPresented: Binding(
                    get: { store.isSharingMyKey },
                    set: { if !$0 { store.send(.shareMyKeyDismissed) } }
                )
            ) {
                NewChatMyKeySheet(
                    publicKey: store.myPublicKey,
                    didCopy: store.didCopy,
                    onCopy: { store.send(.copyMyKeyTapped) },
                    onDone: { store.send(.shareMyKeyDismissed) }
                )
            }
        }
    }

    /// Groups are the exception, so they stay behind a deliberate tap rather than making
    /// every DM pass through a multi-select step.
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

    private var primaryButton: some View {
        ZappButton(
            title: primaryTitle,
            isEnabled: store.isPrimaryEnabled,
            leadingIcon: store.primaryAction == .scan ? Asset.Assets.Icons.scan.image : nil
        ) {
            store.send(.primaryTapped)
        }
    }

    private var primaryTitle: String {
        switch store.primaryAction {
        case .scan: return String(localizable: .newChatScan)
        case .start: return String(localizable: .newChatStart)
        case .createGroup, .confirmGroup: return String(localizable: .groupCreate)
        }
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

    /// One field, two jobs: it filters the contacts below and takes a pasted key.
    private var searchField: some View {
        HStack(spacing: Design.Spacing._sm) {
            Asset.Assets.Icons.search.image
                .zImage(width: Constants.fieldIconSize, height: Constants.fieldIconSize, style: ZappColors.textSubtle)

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

            if store.searchInput.isEmpty {
                Button {
                    store.send(.pasteTapped)
                } label: {
                    Text(String(localizable: .newChatPaste))
                        .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
                }
            } else {
                clearButton
            }
        }
        .padding(.horizontal, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._lg)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(
                    (store.searchInput.isEmpty ? ZappColors.border : ZappColors.borderStrong).color(colorScheme),
                    lineWidth: store.searchInput.isEmpty ? 1 : 2
                )
        }
    }

    private var clearButton: some View {
        Button {
            store.send(.searchCleared)
        } label: {
            Asset.Assets.Icons.xClose.image
                .zImage(width: Constants.fieldIconSize, height: Constants.fieldIconSize, style: ZappColors.textSubtle)
        }
        .accessibilityLabel(String(localizable: .newChatClear))
    }

    /// A complete key is a recipient, not text to keep editing — so it replaces the field
    /// rather than being echoed underneath it.
    private var recipientCard: some View {
        HStack(spacing: Design.Spacing._lg) {
            Asset.Assets.Icons.checkVerified.image
                .zImage(width: Constants.cardIconSize, height: Constants.cardIconSize, style: ZappColors.accentText)

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(String(localizable: .newChatKeyDetected))
                    .zappFont(.caption, style: ZappColors.accentText)

                Text(store.detectedContact?.name ?? PublicKeyRules.abbreviated(store.detectedKey))
                    .zappFont(.mono, style: ZappColors.accentText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.isGroupMode && !store.isDetectedKeySelected {
                Button {
                    store.send(.detectedKeyAdded)
                } label: {
                    Text(String(localizable: .newChatAdd))
                        .zappFont(.buttonSmall, color: ZappColors.accentText.color(colorScheme))
                }
            }

            clearButton
        }
        .padding(Design.Spacing._xl)
        .frame(maxWidth: .infinity)
        .background(ZappColors.accentSoft.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
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

    private var emptyState: some View {
        VStack(spacing: Design.Spacing._lg) {
            Asset.Assets.Icons.messageChat.image
                .zImage(width: Constants.emptyIconSize, height: Constants.emptyIconSize, style: ZappColors.textSubtle)
                .frame(width: Constants.emptyIconBox, height: Constants.emptyIconBox)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            Text(String(localizable: .newChatEmptyTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)
                .multilineTextAlignment(.center)

            Text(String(localizable: .newChatEmptyBody))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: Design.Spacing._lg) {
                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(width: Constants.calloutMarkSize, height: Constants.calloutMarkSize)

                Text(String(localizable: .newChatPrivacyCallout))
                    .zappFont(.body, style: ZappColors.accentText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Design.Spacing._xl)
            .frame(maxWidth: .infinity)
            .background(ZappColors.accentSoft.color(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing._xl)
    }

    @ViewBuilder private var contacts: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(
                text: store.isGroupMode
                    ? String(localizable: .groupSelectMembers)
                    : String(localizable: .newChatContactsLabel)
            )

            if store.filteredContacts.isEmpty {
                Text(
                    store.visibleContacts.isEmpty
                        ? String(localizable: .newChatNoContacts)
                        : String(localizable: .newChatNoMatches)
                )
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

    private var rowDivider: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(height: 1)
            .padding(.leading, NewChatContactRow.dividerInset)
    }

    /// Chat is symmetric: the peer needs our key just as much as we need theirs. Kept to a
    /// single row here — the scannable code lives in the sheet, not dumped on the screen.
    private var shareMyKeyRow: some View {
        Button {
            store.send(.shareMyKeyTapped)
        } label: {
            HStack(spacing: Design.Spacing._lg) {
                Asset.Assets.Icons.qr.image
                    .zImage(width: Constants.cardIconSize, height: Constants.cardIconSize, style: ZappColors.text)

                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(String(localizable: .newChatYourKey))
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Text(String(localizable: .newChatYourKeyHint))
                        .zappFont(.caption, style: ZappColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Asset.Assets.Icons.arrowRight.image
                    .zImage(width: Constants.fieldIconSize, height: Constants.fieldIconSize, style: ZappColors.textMuted)
            }
            .padding(Design.Spacing._xl)
            .frame(maxWidth: .infinity)
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .padding(.top, Design.Spacing._md)
    }

    private enum Constants {
        static let fieldIconSize: CGFloat = 18
        static let cardIconSize: CGFloat = 20
        static let emptyIconSize: CGFloat = 40
        static let emptyIconBox: CGFloat = 96
        static let calloutMarkSize: CGFloat = 8
    }
}

/// Our own key, big enough to scan, so the exchange works in whichever direction the two
/// people happen to be standing.
private struct NewChatMyKeySheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let qrSize: CGFloat = 220
    }

    let publicKey: String
    let didCopy: Bool
    let onCopy: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Design.Spacing._xl) {
            ZappScreenHeader(title: String(localizable: .newChatYourKey))

            ChatIdentityQRCode(publicKey: publicKey, size: Constants.qrSize)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surface.color(colorScheme))
                .overlay {
                    Rectangle()
                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                }

            Text(String(localizable: .chatProfileQrCaption))
                .zappFont(.caption, style: ZappColors.textSubtle)
                .multilineTextAlignment(.center)

            Text(publicKey)
                .zappFont(.mono, style: ZappColors.text)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            Spacer(minLength: 0)

            ZappButton(
                title: didCopy ? String(localizable: .newChatCopied) : String(localizable: .newChatCopy),
                variant: .secondary,
                leadingIcon: didCopy ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image,
                action: onCopy
            )

            ZappButton(title: String(localizable: .generalClose), action: onDone)
        }
        .padding(.horizontal, Design.Spacing._lg)
        .padding(.bottom, Design.Spacing._lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
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

                    Text(PublicKeyRules.abbreviated(contact.publicKey))
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
                Asset.Assets.Icons.checkSolid.image
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
