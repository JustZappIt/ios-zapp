// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

/// What a tapped invite link looks like: the group, what joining reveals, and then the answer.
struct GroupInviteView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<GroupInvite>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .groupInviteHeader))

                ScrollView {
                    VStack(spacing: Design.Spacing._lg) {
                        groupMark
                        Spacer().frame(height: Design.Spacing._xs)

                        if let titleText {
                            Text(titleText)
                                .zappFont(.sectionTitle, style: ZappColors.text)
                                .multilineTextAlignment(.center)
                        } else {
                            ProgressView()
                        }

                        if let subtitleText {
                            Text(subtitleText)
                                .zappFont(.body, style: ZappColors.textMuted)
                                .multilineTextAlignment(.center)
                        }

                        if store.sendFailed {
                            Text(String(localizable: .groupInviteSendFailed))
                                .zappFont(.caption, style: ZappColors.danger)
                                .multilineTextAlignment(.center)
                        }
                        Spacer().frame(height: Design.Spacing._lg)
                        actions
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Design.Spacing._3xl)
                    .padding(.vertical, Design.Spacing._4xl)
                }

                ZappBottomActionBar(onBack: back)
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.teardown) }
        }
    }

    private var groupMark: some View {
        ZStack {
            Circle()
                .fill(ZappColors.surfaceAlt.color(colorScheme))
                .frame(width: 72, height: 72)
            Asset.Assets.Icons.users.image
                .zImage(width: 24, height: 24, style: ZappColors.text)
        }
    }

    private var titleText: String? {
        switch store.stage {
        case .reading:
            return nil
        case .preview(let name), .requesting(let name):
            return named(name) { String(localizable: .groupInviteTitleNamed($0)) }
                ?? String(localizable: .groupInviteTitle)
        case .waiting:
            return String(localizable: .groupInviteWaitingTitle)
        case let .joined(_, name, alreadyMember):
            if alreadyMember { return String(localizable: .groupInviteAlreadyMember) }
            return named(name) { String(localizable: .groupInviteJoinedNamed($0)) }
                ?? String(localizable: .groupInviteJoined)
        case .failed(let reason):
            return Self.failureText(reason)
        case .comingSoon:
            return String(localizable: .groupInviteComingSoon)
        }
    }

    private var subtitleText: String? {
        switch store.stage {
        case .preview, .requesting:
            return String(localizable: .groupInviteBody)
        case .waiting(_, _, let progress):
            switch progress {
            case .queued: return String(localizable: .groupInviteWaitingQueued)
            case .sent: return String(localizable: .groupInviteWaitingBody)
            case .withOwner: return String(localizable: .groupInviteWaitingOwner)
            }
        default:
            return nil
        }
    }

    static func failureText(_ reason: GroupInvite.Failure) -> String {
        switch reason {
        case .unreadable: return String(localizable: .groupInviteUnreadable)
        case .expired: return String(localizable: .groupInviteExpired)
        case .needsUpdate: return String(localizable: .groupInviteUpdate)
        case .inactive: return String(localizable: .groupInviteInactive)
        case .full: return String(localizable: .groupInviteFull)
        case .declined: return String(localizable: .groupInviteDeclined)
        }
    }

    /// The group's own name, when the link carried one. A link without a name says less, and the
    /// copy has to say less with it.
    private func named(_ name: String?, _ withName: (String) -> String) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return withName(name)
    }

    @ViewBuilder
    private var actions: some View {
        switch store.stage {
        case .preview:
            ZappButton(title: String(localizable: .groupInviteJoin)) { store.send(.joinTapped) }
            ZappButton(title: String(localizable: .groupInviteNotNow), variant: .ghost) {
                store.send(.notNowTapped)
            }

        case .requesting:
            ZappButton(title: String(localizable: .groupInviteJoin), isLoading: true) { }

        case .waiting:
            ZappButton(title: String(localizable: .groupInviteCancel), variant: .ghost) {
                store.send(.cancelTapped)
            }

        case .joined(let conversationId, _, _):
            if let conversationId {
                ZappButton(title: String(localizable: .groupInviteOpenGroup)) {
                    store.send(.openGroupTapped(conversationId))
                }
            }

        case .reading, .failed, .comingSoon:
            EmptyView()
        }
    }

    private func back() {
        switch store.stage {
        case .reading, .preview: store.send(.notNowTapped)
        default: store.send(.delegate(.dismiss))
        }
    }
}
