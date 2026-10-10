//
//  ChatNetworkStatusView.swift
//  Zapp
//

import SwiftUI
import ZappMessaging

enum ChatNetworkChipContext: Equatable {
    case list
    case room
}

/// Android's `ChatListConnectionStatus`: the four states every chip, subtitle and the details
/// sheet start from.
enum ChatConnectionStatus: Equatable {
    case connecting
    case connected
    case disconnected
    case error
}

extension ZappMessagingState {
    var connectionStatus: ChatConnectionStatus {
        switch phase {
        case .ready: return isOnline ? .connected : .disconnected
        case .failed: return .error
        case .initializing, .deriving, .idle, .needsIdentity: return .connecting
        }
    }

    /// The room header's subtitle, always present as on Android (`ChatRoomVM.subtitleText`).
    ///
    /// Android also says "Peer offline, messages queued" once a peer's presence turns offline.
    /// The iOS client only tracks who is online, not who went offline, so that case reads as
    /// the unknown one, "Waiting for peer…".
    func roomSubtitle(for conversationId: String) -> String {
        switch connectionStatus {
        case .connecting: return String(localizable: .chatRoomSubtitleConnecting)
        case .disconnected: return String(localizable: .chatRoomSubtitleOffline)
        case .error: return String(localizable: .chatRoomSubtitleError)
        case .connected: break
        }

        if isPeerOnline(in: conversationId) { return String(localizable: .chatRoomSubtitlePeerOnline) }
        if dhtHealth == "critical" { return String(localizable: .chatRoomSubtitleDhtUnreachable) }
        // Reachable, but their presence is not ours to show.
        if isPeerReachable(in: conversationId) { return String(localizable: .chatRoomSubtitleP2pConnected) }
        if dhtHealth == "degraded" { return String(localizable: .chatRoomSubtitleDhtDegraded) }

        return String(localizable: .chatRoomSubtitleWaitingForPeer)
    }
}

struct ChatNetworkStatusChip: View {
    let state: ZappMessagingState
    let context: ChatNetworkChipContext
    var conversationId: String? = nil
    let action: () -> Void

    var body: some View {
        ZappStatusChip(
            text: model.text,
            variant: model.variant,
            dotColor: model.dotColor,
            action: action
        )
    }

    private var model: (text: String, variant: ZappChipVariant, dotColor: ZappColors) {
        switch state.connectionStatus {
        case .connecting:
            return (String(localizable: .chatListStatusConnecting), .accent, .accent)
        case .disconnected:
            return context == .room
                ? (String(localizable: .chatRoomChipOff), .danger, .danger)
                : (String(localizable: .chatListStatusDisconnected), .danger, .danger)
        case .error:
            return context == .room
                ? (String(localizable: .chatRoomChipErr), .danger, .danger)
                : (String(localizable: .chatListStatusError), .danger, .danger)
        case .connected:
            break
        }

        // The list chip is the swarm's peer count, zero included (`ChatListVM.networkChipText`).
        guard context == .room else {
            return (String(state.peerCount), .success, .success)
        }

        // A room chip speaks for one conversation, so it answers about that peer first
        // (`ChatRoomVM.chipText`). Reachability is ungated on purpose: hiding our own status
        // must not strand a working conversation on "…".
        if let conversationId, state.isPeerOnline(in: conversationId) {
            return (String(localizable: .chatRoomChipOnline), .success, .success)
        }
        if state.dhtHealth == "critical" {
            return (String(localizable: .chatRoomChipDht), .danger, .danger)
        }
        if let conversationId, state.isPeerReachable(in: conversationId) {
            return (String(localizable: .chatRoomChipConnected), .success, .success)
        }

        return (String(localizable: .chatListStatusConnecting), .accent, .accent)
    }
}

/// Android's `NetworkDetailsSheet`. Rows that need the connection details stay hidden until
/// they load, rather than showing placeholders. Refresh, close and the latest-issue section are
/// iOS additions.
struct ChatNetworkDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private enum Constants {
        static let iconSize: CGFloat = 18
        static let closeIconSize: CGFloat = 14
        static let closeTarget: CGFloat = 36
        static let dividerOpacity: CGFloat = 0.3
    }

    let state: ZappMessagingState
    let details: ZMConnectionDetails?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                header

                sectionHeader(String(localizable: .chatNetworkSectionConnection))

                row(
                    Asset.Assets.Icons.server.image,
                    String(localizable: .chatNetworkStatus),
                    connectionValue,
                    connectionColor
                )

                if let details {
                    row(
                        Asset.Assets.Icons.switchHorizontal.image,
                        String(localizable: .chatNetworkReachability),
                        reachabilityValue(details),
                        reachabilityColor(details)
                    )
                    row(
                        Asset.Assets.Icons.downloadCloud.image,
                        String(localizable: .chatNetworkBackup),
                        backupValue(details),
                        backupColor(details)
                    )
                }

                divider

                sectionHeader(String(localizable: .chatNetworkSectionPeers))

                row(
                    Asset.Assets.Icons.users.image,
                    String(localizable: .chatNetworkPeers),
                    String(peerCount),
                    peerCount > 0 ? .success : .textMuted
                )

                if let details {
                    row(
                        Asset.Assets.Icons.chainLink.image,
                        String(localizable: .chatNetworkConnections),
                        String(details.globalConnections),
                        .text
                    )
                }

                row(Asset.Assets.Icons.layersThree.image, String(localizable: .chatNetworkDht), dhtValue, dhtColor)

                if let details {
                    row(
                        Asset.Assets.Icons.integrations.image,
                        String(localizable: .chatNetworkNodes),
                        String(details.rtNodes),
                        details.rtNodes > 0 ? .success : .textMuted
                    )

                    divider

                    sectionHeader(String(localizable: .chatNetworkSectionMessages))

                    row(
                        Asset.Assets.Icons.clockCheck.image,
                        String(localizable: .chatNetworkPending),
                        pendingValue(details),
                        details.pendingMessageCount > 0 ? .accent : .success
                    )
                    row(
                        Asset.Assets.Icons.messageChat.image,
                        String(localizable: .chatNetworkConversations),
                        String(
                            localizable: .chatNetworkConversationCount(
                                String(details.directConversations),
                                String(details.groupConversations)
                            )
                        ),
                        .text
                    )
                    row(
                        Asset.Assets.Icons.userPlus.image,
                        String(localizable: .chatNetworkInvites),
                        String(details.pendingInvites),
                        details.pendingInvites > 0 ? .accent : .textMuted
                    )
                }

                if let failure = state.lastFailure {
                    divider

                    sectionHeader(String(localizable: .chatNetworkSectionLastError))

                    VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                        Text("\(failure.operation.identifier) · \(failure.code.identifier)")
                            .zappFont(
                                .rowTitle,
                                style: failure.severity == .error ? ZappColors.danger : ZappColors.accentText
                            )
                        Text(failure.message)
                            .zappFont(.caption, style: ZappColors.text)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Design.Spacing._xl)
            .padding(.bottom, Design.Spacing._3xl)
        }
        .background(ZappColors.bg.color(colorScheme))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text(String(localizable: .chatNetworkTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Spacer()

            if isLoading {
                ProgressView().tint(ZappColors.accent.color(colorScheme))
            } else {
                Button(String(localizable: .chatNetworkRefresh), action: onRefresh)
                    .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
            }

            Button(action: { dismiss() }) {
                Asset.Assets.Icons.xClose.image
                    .zImage(width: Constants.closeIconSize, height: Constants.closeIconSize, style: ZappColors.text)
                    .frame(width: Constants.closeTarget, height: Constants.closeTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .generalClose))
        }
        .padding(.top, Design.Spacing._lg)
    }

    private var divider: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme).opacity(Constants.dividerOpacity))
            .frame(height: 1)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .zappFont(.groupLabel, style: ZappColors.textMuted)
    }

    private func row(_ icon: Image, _ label: String, _ value: String, _ valueColor: ZappColors) -> some View {
        HStack(spacing: Design.Spacing._sm) {
            icon
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.textMuted)

            Text(label)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer(minLength: Design.Spacing._md)

            Text(value)
                .zappFont(.body, style: valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var peerCount: Int { details?.peerCount ?? state.peerCount }

    private var connectionValue: String {
        switch state.connectionStatus {
        case .connected: return String(localizable: .chatNetworkConnected)
        case .connecting: return String(localizable: .chatNetworkConnecting)
        case .disconnected: return String(localizable: .chatNetworkDisconnected)
        case .error: return String(localizable: .chatNetworkError)
        }
    }

    private var connectionColor: ZappColors {
        switch state.connectionStatus {
        case .connected: return .success
        case .connecting: return .accent
        case .disconnected, .error: return .danger
        }
    }

    private func reachabilityValue(_ details: ZMConnectionDetails) -> String {
        if details.dhtFirewalled == false { return String(localizable: .chatNetworkDirect) }
        if details.dhtRandomized == true { return String(localizable: .chatNetworkStrictNat) }
        if details.dhtFirewalled == true { return String(localizable: .chatNetworkNat) }
        return String(localizable: .generalUnknown)
    }

    private func reachabilityColor(_ details: ZMConnectionDetails) -> ZappColors {
        if details.dhtFirewalled == false { return .success }
        if details.dhtFirewalled == true || details.dhtRandomized == true { return .accent }
        return .textMuted
    }

    /// Relay backup the user turned off reads "Off", not "Unavailable": it isn't a fault.
    private func backupValue(_ details: ZMConnectionDetails) -> String {
        if !details.relayEnabled { return String(localizable: .chatNetworkOff) }
        if details.relaysConnected > 0 { return String(localizable: .chatNetworkConnected) }
        if details.relaysTotal > 0 { return String(localizable: .chatNetworkUnavailable) }
        return String(localizable: .chatNetworkOff)
    }

    private func backupColor(_ details: ZMConnectionDetails) -> ZappColors {
        if !details.relayEnabled { return .textMuted }
        if details.relaysConnected > 0 { return .success }
        return details.relaysTotal > 0 ? .accent : .textMuted
    }

    /// A health the core hasn't reported yet (still connecting, or after a boot failure) reads
    /// "Unknown", not a green "Healthy" under a status row that says otherwise.
    private var dhtValue: String {
        switch details?.dhtHealth ?? state.dhtHealth {
        case "healthy": return String(localizable: .chatNetworkDhtHealthy)
        case "degraded": return String(localizable: .chatNetworkDhtDegraded)
        case "critical": return String(localizable: .chatNetworkDhtCritical)
        default: return String(localizable: .generalUnknown)
        }
    }

    private var dhtColor: ZappColors {
        switch details?.dhtHealth ?? state.dhtHealth {
        case "healthy": return .success
        case "degraded": return .accent
        case "critical": return .danger
        default: return .textMuted
        }
    }

    private func pendingValue(_ details: ZMConnectionDetails) -> String {
        guard details.pendingMessageCount > 0 else { return String(localizable: .chatNetworkNone) }

        return String(
            localizable: .chatNetworkPendingCount(
                String(details.pendingMessageCount),
                String(details.pendingQueues)
            )
        )
    }
}
