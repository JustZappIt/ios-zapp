//
//  GroupInfoView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct GroupInfoView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<GroupInfo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .groupInfoTitle)) {
                    ZappBackButton { store.send(.backToHomeTapped) }
                } right: {
                    EmptyView()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                        nameSection
                        members
                        addMemberButton

                        if store.didFail {
                            Text(String(localizable: .chatProfileSaveFailed))
                                .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
                        }

                        leaveButton
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

    @ViewBuilder private var nameSection: some View {
        if store.isRenaming {
            renameField
        } else {
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(store.conversation.displayName)
                    .zappFont(.display, style: ZappColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Only the creator can rename. Offering the control to anyone else would
                // produce a call the core rejects.
                if store.canRename {
                    ZappButton(
                        title: String(localizable: .groupRename),
                        variant: .accentGhost,
                        isEnabled: !store.isMutating
                    ) {
                        store.send(.renameTapped)
                    }
                }
            }
        }
    }

    private var renameField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .groupName))

            TextField(
                String(localizable: .groupNamePlaceholder),
                text: Binding(
                    get: { store.nameDraft ?? "" },
                    set: { store.send(.nameDraftChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .autocorrectionDisabled()
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))

            HStack(spacing: Design.Spacing._md) {
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
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            ZappSectionLabel(text: String(localizable: .groupMembers))

            VStack(spacing: 0) {
                ForEach(store.state.members) { member in
                    GroupMemberRow(member: member)

                    if member.id != store.state.members.last?.id {
                        ZappRowDivider(inset: true)
                    }
                }
            }
        }
    }

    private var addMemberButton: some View {
        ZappButton(
            title: String(localizable: .groupAddMember),
            variant: .secondary,
            isEnabled: !store.isMutating,
            leadingIcon: Asset.Assets.Icons.userPlus.image
        ) {
            store.send(.addMemberTapped)
        }
        .frame(maxWidth: .infinity)
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
        .padding(.top, Design.Spacing._lg)
    }

    private var addMemberSheet: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            Text(String(localizable: .groupSelectMembers))
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.horizontal, Design.Spacing._lg)
                .padding(.top, Design.Spacing._2xl)

            if store.state.addableContacts.isEmpty {
                Text(String(localizable: .newChatNoContacts))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .padding(.horizontal, Design.Spacing._lg)
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
        .background(ZappColors.bg.color(colorScheme))
    }
}

private enum GroupRowConstants {
    static let avatarSize: CGFloat = 40
    static let spacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 10
}

/// The roster carries no presence: the core never tells us whether a given member is reachable,
/// only whether *we* are. A dot here would report our own connectivity under their name.
private struct GroupMemberRow: View {
    let member: GroupMember

    var body: some View {
        HStack(spacing: GroupRowConstants.spacing) {
            GroupAvatar(name: member.name)

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(member.name)
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(member.publicKey.zappEllipsized())
                    .zappFont(.mono, style: ZappColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if member.isOwner {
                ZappStatusChip(text: String(localizable: .groupOwner), variant: .accent)
            }
        }
        .padding(.horizontal, GroupRowConstants.horizontalPadding)
        .padding(.vertical, GroupRowConstants.verticalPadding)
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
            .padding(.horizontal, Design.Spacing._lg)
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

    var body: some View {
        Text(name.zappInitials)
            .zappFont(.rowTitle, style: ZappColors.onAccent)
            .frame(width: GroupRowConstants.avatarSize, height: GroupRowConstants.avatarSize)
            .background(ZappColors.accent.color(colorScheme))
    }
}

#Preview {
    GroupInfoView(store: GroupInfo.initial)
}
