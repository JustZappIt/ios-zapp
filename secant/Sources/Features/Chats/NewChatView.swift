//
//  NewChatView.swift
//  Zapp
//
//  Android's `NewConversationView`: chips and contacts above, the search field and the dock
//  at the bottom where the thumb already is.
//

import ComposableArchitecture
import SwiftUI

struct NewChatView: View {
    private enum Field: Hashable {
        case search
        case groupName
    }

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    @Perception.Bindable var store: StoreOf<NewChat>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .newChatTitle))

                if store.showsEmptyState {
                    emptyState
                        .padding(.horizontal, Constants.emptyStatePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        conversationBody
                            .padding(.horizontal, Design.Spacing._lg)
                            .padding(.vertical, Design.Spacing._lg)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }

                searchField
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.vertical, Design.Spacing._md)

                ZappBottomActionBar(
                    onBack: { store.send(.backToHomeTapped) },
                    isBackEnabled: !store.isCreating
                ) {
                    primaryButton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .overlay {
                if store.isNamingGroup {
                    groupNameDialog
                }
            }
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

    private var conversationBody: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            if !store.participants.isEmpty {
                ZappFlowLayout(spacing: Constants.chipSpacing, lineSpacing: Constants.chipLineSpacing) {
                    ForEach(store.participants) { participant in
                        NewChatParticipantChip(name: participant.name) {
                            store.send(.participantRemoved(participant.publicKey))
                        }
                    }
                }
            }

            if store.showsDetectedKey {
                detectedKeyBanner
            }

            if store.isOwnKey {
                Text(String(localizable: .newChatOwnKey))
                    .zappFont(.caption, style: ZappColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.errorCode != nil && store.errorCode != .ownPublicKey && !store.isNamingGroup {
                Text(String(localizable: .newChatFailed))
                    .zappFont(.caption, style: ZappColors.danger)
            }

            contacts
        }
    }

    private var primaryButton: some View {
        ZappButton(
            title: store.primaryAction == .scan
                ? String(localizable: .newChatScan)
                : String(localizable: .newChatStart),
            isEnabled: store.isPrimaryEnabled,
            leadingIcon: store.primaryAction == .scan ? Asset.Assets.Icons.scan.image : nil
        ) {
            store.send(.primaryTapped)
        }
    }

    /// One field, two jobs: it filters the contacts above and takes a pasted key.
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
            .focused($focusedField, equals: .search)
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
                Button {
                    store.send(.searchCleared)
                } label: {
                    Asset.Assets.Icons.xClose.image
                        .zImage(width: Constants.fieldIconSize, height: Constants.fieldIconSize, style: ZappColors.textSubtle)
                }
                .accessibilityLabel(String(localizable: .newChatClear))
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
        .zappFieldTapTarget($focusedField, equals: .search)
    }

    /// Android's `PublicKeyDetectedBanner`: the whole banner adds the key as a chip.
    private var detectedKeyBanner: some View {
        Button {
            store.send(.detectedKeyAdded)
        } label: {
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

                if store.canAddDetectedKey {
                    Text(String(localizable: .newChatAdd))
                        .zappFont(.button, style: ZappColors.accentText)
                }
            }
            .padding(Design.Spacing._lg)
            .frame(maxWidth: .infinity)
            .background(ZappColors.accentSoft.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(!store.canAddDetectedKey)
    }

    /// Android's `GroupNameDialog`.
    private var groupNameDialog: some View {
        ZappDialog(onScrimTap: store.isCreating ? nil : { store.send(.groupCancelTapped) }) {
            Text(String(localizable: .newChatGroupNameTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            TextField(
                String(localizable: .groupName),
                text: Binding(
                    get: { store.groupName },
                    set: { store.send(.groupNameChanged($0)) }
                )
            )
            .focused($focusedField, equals: .groupName)
            .zappFont(.body, style: ZappColors.text)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { store.send(.groupConfirmTapped) }
            .disabled(store.isCreating)
            .padding(Design.Spacing._lg)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .zappFieldTapTarget($focusedField, equals: .groupName)

            if store.errorCode != nil {
                Text(String(localizable: .newChatFailed))
                    .zappFont(.caption, style: ZappColors.danger)
            }

            HStack(spacing: Design.Spacing._lg) {
                ZappButton(
                    title: String(localizable: .generalCancel),
                    variant: .ghost,
                    isEnabled: !store.isCreating
                ) {
                    store.send(.groupCancelTapped)
                }

                ZappButton(
                    title: String(localizable: .groupCreate),
                    isEnabled: store.canConfirmGroup
                ) {
                    store.send(.groupConfirmTapped)
                }
            }
        }
        .onAppear { focusedField = .groupName }
    }

    /// Android's `NewConversationEmptyState`, shown only when there is nobody to list.
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

            HStack(alignment: .top, spacing: Design.Spacing._md) {
                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(width: Constants.calloutMarkSize, height: Constants.calloutMarkSize)
                    .padding(.top, Constants.calloutMarkOffset)

                Text(String(localizable: .newChatPrivacyCallout))
                    .zappFont(.body, style: ZappColors.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Spacing._lg)
            .background(ZappColors.accentSoft.color(colorScheme))
        }
    }

    @ViewBuilder private var contacts: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatContactsLabel))

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

    private enum Constants {
        static let fieldIconSize: CGFloat = 18
        static let cardIconSize: CGFloat = 20
        static let emptyIconSize: CGFloat = 52
        static let emptyIconBox: CGFloat = 100
        static let emptyStatePadding: CGFloat = 28
        static let calloutMarkSize: CGFloat = 8
        static let calloutMarkOffset: CGFloat = 6
        static let chipSpacing: CGFloat = 8
        static let chipLineSpacing: CGFloat = 6
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

            ChatIdentityQRCode(payload: publicKey, size: Constants.qrSize)
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
        .accessibilityLabel(String(localizable: .newChatRemoveParticipant(name)))
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

                // Android marks only the picked rows; an unpicked row carries no control.
                if isSelected {
                    selectionBox
                        .accessibilityLabel(String(localizable: .newChatSelected))
                }
            }
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    private var selectionBox: some View {
        Asset.Assets.Icons.checkSolid.image
            .zImage(width: Constants.checkIconSize, height: Constants.checkIconSize, style: ZappColors.onAccent)
            .frame(width: Constants.checkboxSize, height: Constants.checkboxSize)
            .background(ZappColors.accent.color(colorScheme))
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
