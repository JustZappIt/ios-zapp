//
//  GroupInfoView.swift
//  Zapp
//
//  Android's `GroupInfoSheet`: a sheet over the room, so dismissing it lands back in the
//  conversation it describes.
//

import ComposableArchitecture
import SwiftUI

struct GroupInfoView: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNameFocused: Bool

    @Perception.Bindable var store: StoreOf<GroupInfo>

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, Design.Spacing._lg)

                    // Only the creator can rename or add. Offering the controls to anyone else
                    // would produce a call the core rejects.
                    if store.canRename {
                        GroupActionRow(
                            icon: Asset.Assets.Icons.pencil.image,
                            label: String(localizable: .groupRename),
                            isEnabled: !store.isMutating
                        ) {
                            store.send(.renameTapped)
                        }
                    }

                    if store.canAddMember {
                        GroupActionRow(
                            icon: Asset.Assets.Icons.userPlus.image,
                            label: String(localizable: .groupAddMember),
                            isEnabled: !store.isMutating
                        ) {
                            store.send(.addMemberTapped)
                        }
                    }

                    members
                        .padding(.top, Design.Spacing._md)

                    if store.didFail {
                        Text(String(localizable: .chatProfileSaveFailed))
                            .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
                            .padding(.top, Design.Spacing._lg)
                    }

                    leaveButton
                        .padding(.top, Design.Spacing._2xl)
                }
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.top, Design.Spacing._2xl)
                .padding(.bottom, Design.Spacing._2xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.surface.color(colorScheme))
            .overlay {
                if store.isRenaming {
                    renameDialog
                }
            }
            .presentationDetents([.medium, .large])
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .sheet(isPresented: addMemberBinding) {
                // A sheet's content closure escapes: reads inside it only register with TCA's
                // observation system under their own WithPerceptionTracking.
                WithPerceptionTracking {
                    addMemberSheet
                }
            }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    private var addMemberBinding: Binding<Bool> {
        Binding(
            get: { store.isAddMemberPresented },
            set: { isPresented in
                if !isPresented {
                    store.send(.addMemberDismissed)
                }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            Text(store.conversation.displayName)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(localizable: .groupMembersCount(String(store.memberCount))))
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    /// Android's `GroupRenameDialog`.
    private var renameDialog: some View {
        ZappDialog(onScrimTap: { store.send(.renameCancelled) }) {
            Text(String(localizable: .groupRename))
                .zappFont(.sectionTitle, style: ZappColors.text)

            TextField(
                String(localizable: .groupName),
                text: Binding(
                    get: { store.nameDraft ?? "" },
                    set: { store.send(.nameDraftChanged($0)) }
                )
            )
            .focused($isNameFocused)
            .zappFont(.body, style: ZappColors.text)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { store.send(.renameSaveTapped) }
            .padding(Design.Spacing._lg)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .zappFieldTapTarget($isNameFocused)

            HStack(spacing: Design.Spacing._lg) {
                ZappButton(title: String(localizable: .generalCancel), variant: .ghost) {
                    store.send(.renameCancelled)
                }

                ZappButton(
                    title: String(localizable: .generalSave),
                    isEnabled: store.canSaveName
                ) {
                    store.send(.renameSaveTapped)
                }
            }
        }
        .onAppear { isNameFocused = true }
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._sm) {
            Text(String(localizable: .groupMembers).uppercased())
                .zappFont(.eyebrow, style: ZappColors.textSubtle)

            VStack(spacing: 0) {
                ForEach(store.state.members) { member in
                    GroupMemberRow(member: member)
                }
            }
        }
    }

    private var leaveButton: some View {
        ZappButton(
            title: String(localizable: .groupLeave),
            variant: .danger,
            isEnabled: !store.isMutating
        ) {
            store.send(.leaveTapped)
        }
        .frame(maxWidth: .infinity)
    }

    /// Android's `AddMemberSheet`.
    private var addMemberSheet: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            Text(String(localizable: .groupAddMember))
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.top, Design.Spacing._2xl)

            if store.state.addableContacts.isEmpty {
                Text(String(localizable: .groupNoContactsToAdd))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .padding(.horizontal, Design.Spacing._2xl)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.state.addableContacts) { contact in
                            GroupAddableContactRow(contact: contact) {
                                store.send(.memberSelected(contact))
                            }

                            if contact.id != store.state.addableContacts.last?.id {
                                ZappRowDivider(inset: true)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(ZappColors.surface.color(colorScheme))
        .presentationDetents([.medium, .large])
    }
}

private enum GroupRowConstants {
    static let avatarSize: CGFloat = 40
    static let memberAvatarSize: CGFloat = 36
    static let actionIconSize: CGFloat = 24
    static let actionSpacing: CGFloat = 16
    static let actionVerticalPadding: CGFloat = 14
    static let spacing: CGFloat = 12
    static let verticalPadding: CGFloat = 10
    static let memberVerticalPadding: CGFloat = 8
}

/// Android's `GroupActionRow`: an accent icon and a label, the whole row tappable.
private struct GroupActionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: Image
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GroupRowConstants.actionSpacing) {
                icon
                    .zImage(
                        width: GroupRowConstants.actionIconSize,
                        height: GroupRowConstants.actionIconSize,
                        style: ZappColors.accent
                    )

                Text(label)
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, GroupRowConstants.actionVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// The roster carries no presence: the core never tells us whether a given member is reachable,
/// only whether *we* are. A dot here would report our own connectivity under their name.
private struct GroupMemberRow: View {
    let member: GroupMember

    var body: some View {
        HStack(spacing: GroupRowConstants.spacing) {
            GroupAvatar(name: member.name, size: GroupRowConstants.memberAvatarSize, style: .chip)

            Text(member.name)
                .zappFont(.rowTitle, style: ZappColors.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if member.isOwner {
                ZappStatusChip(text: String(localizable: .groupOwner), variant: .accent)
            }
        }
        .padding(.vertical, GroupRowConstants.memberVerticalPadding)
        .frame(maxWidth: .infinity)
    }
}

private struct GroupAddableContactRow: View {
    let contact: ChatContact
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GroupRowConstants.spacing) {
                GroupAvatar(name: contact.name)

                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(contact.name)
                        .zappFont(.rowTitle, style: ZappColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(contact.publicKey.zappEllipsized())
                        .zappFont(.mono, style: ZappColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .padding(.vertical, GroupRowConstants.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }
}

private struct GroupAvatar: View {
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    var size: CGFloat = GroupRowConstants.avatarSize
    var style: ZappTextStyle = .rowTitle

    var body: some View {
        Text(name.zappInitials)
            .zappFont(style, style: ZappColors.onAccent)
            .frame(width: size, height: size)
            .background(ZappColors.accent.color(colorScheme))
    }
}

#Preview {
    GroupInfoView(store: GroupInfo.initial)
}
