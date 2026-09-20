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

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: Design.Spacing._lg) {
                            groupMark

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
                        }
                        .frame(minHeight: geometry.size.height, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                }

                bottomBar
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
            Image(systemName: "person.3.fill")
                .foregroundColor(ZappColors.text.color(colorScheme))
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
        case .joined(_, let name, let alreadyMember):
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
        case .waiting(_, let withOwner):
            return withOwner
                ? String(localizable: .groupInviteWaitingOwner)
                : String(localizable: .groupInviteWaitingBody)
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
    private var bottomBar: some View {
        switch store.stage {
        case .preview:
            ZappBottomActionBar(onBack: { store.send(.notNowTapped) }) {
                VStack(spacing: Design.Spacing._md) {
                    ZappButton(title: String(localizable: .groupInviteJoin)) { store.send(.joinTapped) }
                    ZappButton(title: String(localizable: .groupInviteNotNow), variant: .ghost) {
                        store.send(.notNowTapped)
                    }
                }
            }

        case .requesting:
            ZappBottomActionBar(onBack: { store.send(.notNowTapped) }) {
                ZappButton(title: String(localizable: .groupInviteJoin), isEnabled: false) { }
            }

        case .waiting:
            ZappBottomActionBar(onBack: { store.send(.delegate(.dismiss)) }) {
                ZappButton(title: String(localizable: .groupInviteCancel), variant: .ghost) {
                    store.send(.cancelTapped)
                }
            }

        case .joined(let conversationId, _, _):
            ZappBottomActionBar(onBack: { store.send(.delegate(.dismiss)) }) {
                if let conversationId {
                    ZappButton(title: String(localizable: .groupInviteOpenGroup)) {
                        store.send(.openGroupTapped(conversationId))
                    }
                }
            }

        case .reading, .failed, .comingSoon:
            ZappBottomActionBar(onBack: { store.send(.delegate(.dismiss)) }) { EmptyView() }
        }
    }
}
