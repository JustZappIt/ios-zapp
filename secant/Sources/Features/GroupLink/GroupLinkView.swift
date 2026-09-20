// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

/// The owner's invite link: the link itself, what sharing it means, and the controls over it.
struct GroupLinkView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<GroupLink>

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                VStack(spacing: 0) {
                    ZappScreenHeader(title: String(localizable: .groupLinkHeader))

                    ScrollView {
                        VStack(spacing: Design.Spacing._lg) {
                            if !store.isOwner {
                                Text(String(localizable: .groupLinkOwnerOnly))
                                    .zappFont(.body, style: ZappColors.textMuted)
                            } else {
                                ownerContent
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Design.Spacing._lg)
                        .padding(.vertical, Design.Spacing._lg)
                    }

                    ZappBottomActionBar(onBack: { store.send(.backTapped) }) { EmptyView() }
                }
                .applyScreenBackground()

                if store.isConfirmingReset {
                    resetDialog
                }
            }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .confirmationDialog(
                String(localizable: .groupLinkExpiryLabel),
                isPresented: Binding(
                    get: { store.picker == .expiry },
                    set: { if !$0 { store.send(.pickerDismissed) } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(GroupLink.expiryChoices.indices, id: \.self) { index in
                    let days = GroupLink.expiryChoices[index]
                    Button(expiryChoiceTitle(days)) { store.send(.expiryPicked(days)) }
                }
            }
            .confirmationDialog(
                String(localizable: .groupLinkLimitLabel),
                isPresented: Binding(
                    get: { store.picker == .limit },
                    set: { if !$0 { store.send(.pickerDismissed) } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(GroupLink.limitChoices.indices, id: \.self) { index in
                    let limit = GroupLink.limitChoices[index]
                    Button(GroupLink.State.limitText(limit)) { store.send(.limitPicked(limit)) }
                }
            }
            .overlay { shareSheet }
        }
    }

    @ViewBuilder
    private var ownerContent: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }

        if let link = store.link {
            ZappValueCard(value: link) {
                ChatIdentityQRCode(payload: link, size: 72)
            } trailing: {
                Button {
                    store.send(.copyTapped)
                } label: {
                    Image(systemName: store.isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(ZappColors.text.color(colorScheme))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(String(localizable: .groupLinkCopy))
            }
        }

        if store.info != nil {
            Text(String(localizable: .groupLinkWarning))
                .zappFont(.body, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localizable: .groupLinkHistoryNote))
                .zappFont(.caption, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let notice = store.noticeText {
            Text(notice)
                .zappFont(.caption, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let error = store.errorText {
            Text(error)
                .zappFont(.caption, style: ZappColors.danger)
                .fixedSize(horizontal: false, vertical: true)
        }

        actions

        if !store.requests.isEmpty {
            requests
        }

        if store.isActive {
            settings
        }
    }

    @ViewBuilder
    private var actions: some View {
        if store.info == nil {
            if store.didFail {
                ZappButton(title: String(localizable: .groupLinkRetry), isEnabled: !store.isBusy) {
                    store.send(.retryTapped)
                }
            }
        } else if store.isActive {
            ZappButton(title: String(localizable: .groupLinkCopy), isEnabled: !store.isBusy) {
                store.send(.copyTapped)
            }
            ZappButton(
                title: String(localizable: .groupLinkShare),
                variant: .secondary,
                isEnabled: !store.isBusy
            ) {
                store.send(.shareTapped)
            }
            ZappButton(title: String(localizable: .groupLinkReset), variant: .ghost, isEnabled: !store.isBusy) {
                store.send(.resetTapped)
            }
            ZappButton(title: String(localizable: .groupLinkTurnOff), variant: .ghost, isEnabled: !store.isBusy) {
                store.send(.turnOffTapped)
            }
        } else {
            ZappButton(title: String(localizable: .groupLinkTurnOn), isEnabled: !store.isBusy) {
                store.send(.turnOnTapped)
            }
        }
    }

    private var requests: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            Text(String(localizable: .groupLinkRequestsLabel))
                .zappFont(.eyebrow, style: ZappColors.textSubtle)

            ForEach(store.requests) { request in
                VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                    Text(request.joinerName)
                        .zappFont(.rowTitle, style: ZappColors.text)
                    Text(String(localizable: .groupLinkRequestSubtitle))
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                    if let contactName = store.state.contactName(for: request.joinerKey) {
                        Text(String(localizable: .groupLinkRequestContactFmt(contactName)))
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                    if request.previouslyRemoved {
                        Text(String(localizable: .groupLinkRequestRemovedBefore))
                            .zappFont(.caption, style: ZappColors.textSubtle)
                    }
                    HStack(spacing: Design.Spacing._md) {
                        ZappButton(
                            title: String(localizable: .groupLinkRequestApprove),
                            isEnabled: !store.isBusy
                        ) {
                            store.send(.approveTapped(request.joinerKey))
                        }
                        ZappButton(
                            title: String(localizable: .groupLinkRequestDecline),
                            variant: .ghost,
                            isEnabled: !store.isBusy
                        ) {
                            store.send(.declineTapped(request.joinerKey))
                        }
                    }
                }
                .padding(Design.Spacing._md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ZappColors.surface.color(colorScheme))
                .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
            }
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            ZappRow(
                title: String(localizable: .groupLinkExpiryLabel),
                trailing: {
                    Text(store.state.expiryText(now: Date()))
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                },
                action: { store.send(.pickerOpened(.expiry)) }
            )

            ZappRow(
                title: String(localizable: .groupLinkLimitLabel),
                trailing: {
                    Text(GroupLink.State.limitText(store.info?.maxJoins))
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                },
                action: { store.send(.pickerOpened(.limit)) }
            )

            ZappRow(
                title: String(localizable: .groupLinkNameToggle),
                trailing: {
                    ZappToggle(
                        isOn: store.info?.includeName ?? true,
                        accessibilityLabel: String(localizable: .groupLinkNameToggle)
                    ) {
                        store.send(.nameToggled)
                    }
                },
                action: { store.send(.nameToggled) }
            )

            ZappRow(
                title: String(localizable: .groupLinkApprovalToggle),
                subtitle: String(localizable: .groupLinkApprovalHelp),
                trailing: {
                    ZappToggle(
                        isOn: store.info?.approval == .owner,
                        accessibilityLabel: String(localizable: .groupLinkApprovalToggle)
                    ) {
                        store.send(.approvalToggled)
                    }
                },
                action: { store.send(.approvalToggled) }
            )
        }
        .background(ZappColors.surface.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
    }

    private var resetDialog: some View {
        ZappDialog(onScrimTap: { store.send(.resetDismissed) }) {
            Text(String(localizable: .groupLinkResetTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(String(localizable: .groupLinkResetBody))
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Design.Spacing._lg) {
                ZappButton(title: String(localizable: .groupLinkCancel), variant: .ghost) {
                    store.send(.resetDismissed)
                }
                ZappButton(title: String(localizable: .groupLinkResetConfirm), variant: .danger) {
                    store.send(.resetConfirmed)
                }
            }
        }
    }

    @ViewBuilder
    private var shareSheet: some View {
        if let link = store.linkToShare {
            // The link travels alone: anything added would say something about the group to
            // whatever app the owner picks.
            UIShareDialogView(activityItems: [link]) {
                store.send(.shareFinished)
            }
            .frame(width: 0, height: 0)
        } else {
            EmptyView()
        }
    }

    private func expiryChoiceTitle(_ days: Int?) -> String {
        switch days {
        case .none: return String(localizable: .groupLinkExpiryNever)
        case .some(1): return String(localizable: .groupLinkExpiryOneDay)
        case .some(let value): return String(localizable: .groupLinkExpiryDaysFmt("\(value)"))
        }
    }
}
