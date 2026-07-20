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
        switch state.phase {
        case .initializing, .deriving, .idle, .needsIdentity:
            return (String(localizable: .chatListConnecting), .accent, .accent)
        case .failed:
            return (String(localizable: .chatNetworkError), .danger, .danger)
        case .ready:
            break
        }

        guard state.isOnline else {
            return (String(localizable: .chatListOffline), .danger, .danger)
        }

        if context == .room, let conversationId, state.isPeerOnline(in: conversationId) {
            return (String(localizable: .chatRoomPeerOnline), .success, .success)
        }
        if state.dhtHealth == "critical" {
            return (String(localizable: .chatNetworkDht), .danger, .danger)
        }
        if state.dhtHealth == "degraded" {
            return (String(localizable: .chatListDegraded), .accent, .accent)
        }
        if state.peerCount == 0 {
            return (String(localizable: .chatListConnecting), .accent, .accent)
        }

        return (String(state.peerCount), .success, .success)
    }
}

struct ChatNetworkDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let state: ZappMessagingState
    let details: ZMConnectionDetails?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                header

                section(String(localizable: .chatNetworkSectionConnection)) {
                    row(String(localizable: .chatNetworkStatus), connectionValue, connectionColor)
                    row(String(localizable: .chatNetworkReachability), reachabilityValue, reachabilityColor)
                    row(String(localizable: .chatNetworkBackup), backupValue, backupColor)
                }

                section(String(localizable: .chatNetworkSectionPeers)) {
                    row(String(localizable: .chatNetworkPeers), String(details?.peerCount ?? state.peerCount), peerColor)
                    row(String(localizable: .chatNetworkConnections), String(details?.globalConnections ?? 0), .text)
                    row(String(localizable: .chatNetworkDht), dhtValue, dhtColor)
                    row(String(localizable: .chatNetworkNodes), String(details?.rtNodes ?? 0), nodeColor)
                }

                section(String(localizable: .chatNetworkSectionMessages)) {
                    row(String(localizable: .chatNetworkPending), pendingValue, pendingColor)
                    row(String(localizable: .chatNetworkConversations), conversationValue, .text)
                    row(String(localizable: .chatNetworkInvites), String(details?.pendingInvites ?? 0), inviteColor)
                }

                if let failure = state.lastFailure {
                    section(String(localizable: .chatNetworkSectionLastError)) {
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
                    .zImage(width: 14, height: 14, style: ZappColors.text)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .generalClose))
        }
        .padding(.top, Design.Spacing._lg)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            ZappSectionLabel(text: title)
            content()
        }
        .padding(Design.Spacing._lg)
        .background(ZappColors.surface.color(colorScheme))
    }

    private func row(_ label: String, _ value: String, _ valueColor: ZappColors) -> some View {
        HStack(spacing: Design.Spacing._sm) {
            Text(label)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer(minLength: Design.Spacing._md)

            Text(value)
                .zappFont(.body, style: valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var connectionValue: String {
        if state.phase == .initializing { return String(localizable: .chatListConnecting) }
        return state.isOnline ? String(localizable: .chatNetworkConnected) : String(localizable: .chatListOffline)
    }

    private var connectionColor: ZappColors { state.isOnline ? .success : .danger }

    private var reachabilityValue: String {
        guard let details else { return String(localizable: .generalUnknown) }
        if details.dhtFirewalled == false { return String(localizable: .chatNetworkDirect) }
        if details.dhtRandomized == true { return String(localizable: .chatNetworkStrictNat) }
        if details.dhtFirewalled == true { return String(localizable: .chatNetworkNat) }
        return String(localizable: .generalUnknown)
    }

    private var reachabilityColor: ZappColors {
        details?.dhtFirewalled == false ? .success : .accentText
    }

    private var backupValue: String {
        guard let details else { return String(localizable: .generalUnknown) }
        if !details.relayEnabled { return String(localizable: .chatNetworkOff) }
        if details.relaysConnected > 0 { return String(localizable: .chatNetworkConnected) }
        return String(localizable: .chatNetworkUnavailable)
    }

    private var backupColor: ZappColors {
        guard let details else { return .textMuted }
        if details.relaysConnected > 0 { return .success }
        return details.relayEnabled ? .accentText : .textMuted
    }

    private var peerColor: ZappColors { (details?.peerCount ?? state.peerCount) > 0 ? .success : .textMuted }
    private var nodeColor: ZappColors { (details?.rtNodes ?? 0) > 0 ? .success : .textMuted }

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
        case "critical": return .danger
        default: return .accentText
        }
    }

    private var pendingValue: String {
        guard let details else { return String(localizable: .generalUnknown) }
        guard details.pendingMessageCount > 0 else { return String(localizable: .chatNetworkNone) }
        return "\(details.pendingMessageCount) / \(details.pendingQueues)"
    }

    private var pendingColor: ZappColors { (details?.pendingMessageCount ?? 0) > 0 ? .accentText : .success }
    private var inviteColor: ZappColors { (details?.pendingInvites ?? 0) > 0 ? .accentText : .textMuted }

    private var conversationValue: String {
        guard let details else { return String(localizable: .generalUnknown) }
        return String(
            localizable: .chatNetworkConversationCount(
                String(details.directConversations),
                String(details.groupConversations)
            )
        )
    }
}
