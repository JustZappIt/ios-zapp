// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

/// The owner's invite link: the link itself, what sharing it means, and the controls over it.
struct GroupLinkView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var enlargedLink: String?

    @Perception.Bindable var store: StoreOf<GroupLink>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .groupLinkHeader))

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                        if !store.isOwner {
                            Text(String(localizable: .groupLinkOwnerOnly))
                                .zappFont(.body, style: ZappColors.textMuted)
                        } else {
                            ownerContent
                        }
                        Spacer().frame(height: Design.Spacing._md)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._xl)
                }

                bottomActionBar
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .zashiSheet(isPresented: sheetPresented, horizontalPadding: Design.Spacing._md) {
                sheetContent
            }
            .overlay { shareSheet }
            .zappQRSpotlight(payload: $enlargedLink) { payload, edge in
                ChatIdentityQRCode(payload: payload, size: edge)
            } action: { _ in
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        // The active link has one Share action, like Android. With no link, use the
        // back-only bar so an empty primary-action slot does not draw a bordered card.
        if store.isOwner && store.link != nil {
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(title: String(localizable: .groupLinkShare), isEnabled: !store.isBusy) {
                    store.send(.shareTapped)
                }
            }
        } else {
            ZappBottomActionBar(onBack: { store.send(.backTapped) })
        }
    }

    @ViewBuilder
    private var ownerContent: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }

        if let link = store.link {
            Button {
                enlargedLink = link
            } label: {
                ChatIdentityQRCode(payload: link, size: 240)
            }
            .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(String(localizable: .groupLinkQrContentDescription))
                .accessibilityAddTraits(.isButton)
        }

        if store.isActive {
            Text(String(localizable: .groupLinkWarning))
                .zappFont(.body, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }

        if store.info != nil {
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
        VStack(alignment: .leading, spacing: 0) {
            ZappGroupHeader(text: String(localizable: .groupLinkRequestsLabel))

            VStack(spacing: 0) {
                ForEach(store.requests) { request in
                    WithPerceptionTracking {
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
                                ZappStatusChip(text: String(localizable: .groupLinkRequestRemovedBefore))
                            }
                            HStack(spacing: Design.Spacing._md) {
                                ZappCompactButton(
                                    title: String(localizable: .groupLinkRequestApprove),
                                    variant: .primary,
                                    isEnabled: !store.isBusy
                                ) {
                                    store.send(.approveTapped(request.joinerKey))
                                }
                                ZappCompactButton(
                                    title: String(localizable: .groupLinkRequestDecline),
                                    variant: .primary,
                                    isEnabled: !store.isBusy
                                ) {
                                    store.send(.declineTapped(request.joinerKey))
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, Design.Spacing._lg)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if request.id != store.requests.last?.id {
                            ZappRowDivider(inset: true)
                        }
                    }
                }
            }
            .background(ZappColors.surface.color(colorScheme))
            .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
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

            ZappRowDivider(inset: true)

            ZappRow(
                title: String(localizable: .groupLinkLimitLabel),
                trailing: {
                    Text(GroupLink.State.limitText(store.info?.maxJoins))
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                },
                action: { store.send(.pickerOpened(.limit)) }
            )

            ZappRowDivider(inset: true)

            ZappToggleRow(
                title: String(localizable: .groupLinkNameToggle),
                isOn: store.info?.includeName ?? true,
                isEnabled: !store.isBusy
            ) {
                store.send(.nameToggled)
            }

            ZappRowDivider(inset: true)

            ZappToggleRow(
                title: String(localizable: .groupLinkApprovalToggle),
                subtitle: String(localizable: .groupLinkApprovalHelp),
                isOn: store.info?.approval == .owner,
                isEnabled: !store.isBusy
            ) {
                store.send(.approvalToggled)
            }
        }
        .background(ZappColors.surface.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
    }

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { store.picker != nil || store.isConfirmingReset },
            set: { presented in
                if !presented {
                    store.send(.pickerDismissed)
                    store.send(.resetDismissed)
                }
            }
        )
    }

    @ViewBuilder
    private var sheetContent: some View {
        if store.isConfirmingReset {
            resetConfirmation
        } else if let picker = store.picker {
            pickerContent(picker)
        }
    }

    private func pickerContent(_ picker: GroupLink.Picker) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localizable: picker == .expiry ? .groupLinkExpiryLabel : .groupLinkLimitLabel))
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.horizontal, Design.Spacing._xl)
                .padding(.vertical, Design.Spacing._md)

            if picker == .expiry {
                ForEach(GroupLink.expiryChoices.indices, id: \.self) { index in
                    WithPerceptionTracking {
                        let days = GroupLink.expiryChoices[index]
                        ZappSelectionRow(
                            title: expiryChoiceTitle(days),
                            isSelected: store.state.isExpirySelected(days, now: Date()),
                            isEnabled: !store.isBusy
                        ) {
                            store.send(.expiryPicked(days))
                        }
                    }
                }
            } else {
                ForEach(GroupLink.limitChoices.indices, id: \.self) { index in
                    WithPerceptionTracking {
                        let limit = GroupLink.limitChoices[index]
                        ZappSelectionRow(
                            title: GroupLink.State.limitText(limit),
                            isSelected: store.info?.maxJoins == limit,
                            isEnabled: !store.isBusy
                        ) {
                            store.send(.limitPicked(limit))
                        }
                    }
                }
            }
        }
        .padding(.bottom, Design.Spacing._3xl)
        .background(ZappColors.surface.color(colorScheme))
    }

    private var resetConfirmation: some View {
        VStack(spacing: Design.Spacing._md) {
            Text(String(localizable: .groupLinkResetTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(String(localizable: .groupLinkResetBody))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._lg)

            ZappButton(title: String(localizable: .groupLinkResetConfirm), variant: .danger) {
                store.send(.resetConfirmed)
            }
            ZappButton(title: String(localizable: .groupLinkCancel), variant: .ghost) {
                store.send(.resetDismissed)
            }
        }
        .padding(.horizontal, Design.Spacing._xl)
        .padding(.vertical, Design.Spacing._2xl)
        .background(ZappColors.surface.color(colorScheme))
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
