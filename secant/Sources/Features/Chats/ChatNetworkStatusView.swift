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
            return (chatString("chat.network.connecting", "Connecting…"), .accent, .accent)
        case .failed:
            return (chatString("chat.network.error", "Error"), .danger, .danger)
        case .ready:
            break
        }

        guard state.isOnline else {
            return (chatString("chat.network.offline", "Offline"), .danger, .danger)
        }

        if context == .room {
            if let conversationId, state.isPeerOnline(in: conversationId) {
                return (chatString("chat.network.online", "Online"), .success, .success)
            }
            if state.dhtHealth == "critical" {
                return (chatString("chat.network.dht", "DHT"), .danger, .danger)
            }
            if state.peerCount == 0 {
                return (chatString("chat.network.connecting", "Connecting…"), .accent, .accent)
            }
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

                section(chatString("chat.network.section.connection", "Connection")) {
                    row("wifi", chatString("chat.network.status", "Status"), connectionValue, connectionColor)
                    row("router", chatString("chat.network.reachability", "Reachability"), reachabilityValue, reachabilityColor)
                    row("externaldrive.connected.to.line.below", chatString("chat.network.backup", "Backup delivery"), backupValue, backupColor)
                }

                section(chatString("chat.network.section.peers", "Peers")) {
                    row("person.2", chatString("chat.network.peers", "P2P peers"), String(details?.peerCount ?? state.peerCount), peerColor)
                    row("cable.connector", chatString("chat.network.connections", "TCP connections"), String(details?.globalConnections ?? 0), .text)
                    row("point.3.connected.trianglepath.dotted", "DHT", dhtValue, dhtColor)
                    row("network", chatString("chat.network.nodes", "DHT nodes"), String(details?.rtNodes ?? 0), nodeColor)
                }

                section(chatString("chat.network.section.messages", "Messages")) {
                    row("clock", chatString("chat.network.pending", "Pending"), pendingValue, pendingColor)
                    row("bubble.left.and.bubble.right", chatString("chat.network.conversations", "Conversations"), conversationValue, .text)
                    row("person.badge.plus", chatString("chat.network.invites", "Invites"), String(details?.pendingInvites ?? 0), inviteColor)
                }

                if let failure = state.lastFailure {
                    section(chatString("chat.network.section.lastError", "Last error")) {
                        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                            Text("\(failure.operation) · \(failure.code)")
                                .zappFont(.rowTitle, style: ZappColors.danger)
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
            Text(chatString("chat.network.title", "Network"))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Spacer()

            if isLoading {
                ProgressView().tint(ZappColors.accent.color(colorScheme))
            } else {
                Button(chatString("chat.network.refresh", "Refresh"), action: onRefresh)
                    .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .zImage(width: 14, height: 14, style: ZappColors.text)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(chatString("general.close", "Close"))
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

    private func row(_ icon: String, _ label: String, _ value: String, _ valueColor: ZappColors) -> some View {
        HStack(spacing: Design.Spacing._sm) {
            Image(systemName: icon)
                .zImage(width: 17, height: 17, style: ZappColors.textMuted)
                .frame(width: 22)

            Text(label)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer(minLength: Design.Spacing._md)

            Text(value)
                .zappFont(.body, style: valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var connectionValue: String {
        if state.phase == .initializing { return chatString("chat.network.connecting", "Connecting…") }
        return state.isOnline ? chatString("chat.network.connected", "Connected") : chatString("chat.network.offline", "Offline")
    }

    private var connectionColor: ZappColors { state.isOnline ? .success : .danger }

    private var reachabilityValue: String {
        guard let details else { return chatString("chat.network.unknown", "Unknown") }
        if details.dhtFirewalled == false { return chatString("chat.network.direct", "Direct") }
        if details.dhtRandomized == true { return chatString("chat.network.strictNat", "Strict NAT") }
        if details.dhtFirewalled == true { return "NAT" }
        return chatString("chat.network.unknown", "Unknown")
    }

    private var reachabilityColor: ZappColors {
        details?.dhtFirewalled == false ? .success : .accentText
    }

    private var backupValue: String {
        guard let details else { return chatString("chat.network.unknown", "Unknown") }
        if !details.relayEnabled { return chatString("chat.network.off", "Off") }
        if details.relaysConnected > 0 { return chatString("chat.network.connected", "Connected") }
        return chatString("chat.network.unavailable", "Unavailable")
    }

    private var backupColor: ZappColors {
        guard let details else { return .textMuted }
        if details.relaysConnected > 0 { return .success }
        return details.relayEnabled ? .accentText : .textMuted
    }

    private var peerColor: ZappColors { (details?.peerCount ?? state.peerCount) > 0 ? .success : .textMuted }
    private var nodeColor: ZappColors { (details?.rtNodes ?? 0) > 0 ? .success : .textMuted }

    private var dhtValue: String {
        let health = details?.dhtHealth ?? state.dhtHealth
        return chatString("chat.network.dht.\(health)", health.capitalized)
    }

    private var dhtColor: ZappColors {
        switch details?.dhtHealth ?? state.dhtHealth {
        case "healthy": return .success
        case "critical": return .danger
        default: return .accentText
        }
    }

    private var pendingValue: String {
        guard let details else { return chatString("chat.network.unknown", "Unknown") }
        guard details.pendingMessageCount > 0 else { return chatString("chat.network.none", "None") }
        return "\(details.pendingMessageCount) / \(details.pendingQueues)"
    }

    private var pendingColor: ZappColors { (details?.pendingMessageCount ?? 0) > 0 ? .accentText : .success }
    private var inviteColor: ZappColors { (details?.pendingInvites ?? 0) > 0 ? .accentText : .textMuted }

    private var conversationValue: String {
        guard let details else { return chatString("chat.network.unknown", "Unknown") }
        return "\(details.directConversations) direct · \(details.groupConversations) group"
    }
}

private func chatString(_ key: String, _ defaultValue: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: defaultValue, comment: "")
}
