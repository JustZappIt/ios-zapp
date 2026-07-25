//
//  SupportChatConstants.swift
//  Zapp
//
//  Swift port of `screen/chat/support/SupportChatConstants.kt`.
//
//  A support ticket is NOT a new wire format: it is an ordinary group conversation whose only
//  remote participant is the Zapp support agent's public key. Everything else here is a
//  client-side convention over the SAME `message.send` body both platforms already use — a
//  bot-authored prefix and a category marker — so an iOS ticket is readable by the Android
//  support console and vice versa. Never change these literals on one platform alone.
//

import Foundation
import ZappMessaging

/// The topics offered on the new-ticket picker.
///
/// `rawValue` is the PROTOCOL key: it travels on the wire inside the conversation's display name
/// and inside the `[Category: …]` marker message, so it must never be localized. `displayName`
/// and `greeting` are the localized surfaces and never leave the device.
enum SupportCategory: String, CaseIterable, Equatable, Sendable {
    case problem = "Problem"
    case feedback = "Feedback"
    case other = "Other"

    var protocolKey: String { rawValue }

    var displayName: String {
        switch self {
        case .problem: return String(localizable: .supportChatCategoryProblem)
        case .feedback: return String(localizable: .supportChatCategoryFeedback)
        case .other: return String(localizable: .supportChatCategoryOther)
        }
    }

    var greeting: String {
        switch self {
        case .problem: return String(localizable: .supportChatGreetingProblem)
        case .feedback: return String(localizable: .supportChatGreetingFeedback)
        case .other: return String(localizable: .supportChatGreetingOther)
        }
    }

    static func from(protocolKey: String) -> SupportCategory? {
        SupportCategory(rawValue: protocolKey)
    }
}

enum SupportChatConstants {
    /// The Zapp support agent's Ed25519 public key. Identical to Android's
    /// `SupportChatConstants.SUPPORT_PUBLIC_KEY` — the two platforms must address the same agent.
    static let supportPublicKey = "20dae657c99f8504b4ce052a39b2a6bf3b54023cb56ee2245d9904e4ee0f0c48"

    /// Prefix set on every support-ticket conversation's display name. It is sent over the wire as
    /// part of the group invite so it lands on both peers; the support agent's device depends on
    /// it, because `participantIds` excludes the local user's own key.
    static let displayNamePrefix = "Support: "

    /// Prefix applied to automated messages before they go over the wire. The receiving side uses
    /// it to render the message as if the bot/agent wrote it, even when the sending device was the
    /// user's own.
    static let botPrefix = "[Zapp]: "

    /// The category-selection marker sent when the user picks a topic. Never rendered.
    static let categoryMarkerPrefix = "[Category: "
    static let categoryMarkerSuffix = "]"

    /// The display name a new ticket is created with, e.g. `Support: Problem`.
    static func conversationDisplayName(for category: SupportCategory) -> String {
        "\(displayNamePrefix)\(category.protocolKey)"
    }

    /// Builds the `[Category: <key>]` marker for the given category.
    static func categoryMarker(for category: SupportCategory) -> String {
        "\(categoryMarkerPrefix)\(category.protocolKey)\(categoryMarkerSuffix)"
    }

    /// Parses a category marker message back into the originating category, if recognisable.
    static func parseCategoryMarker(_ message: String) -> SupportCategory? {
        guard message.hasPrefix(categoryMarkerPrefix), message.hasSuffix(categoryMarkerSuffix) else {
            return nil
        }

        let key = message
            .dropFirst(categoryMarkerPrefix.count)
            .dropLast(categoryMarkerSuffix.count)

        return SupportCategory.from(protocolKey: String(key))
    }

    static func isCategoryMarker(_ message: String) -> Bool {
        message.hasPrefix(categoryMarkerPrefix)
    }

    /// Strips the bot prefix if present. Safe on any string — Kotlin's `removePrefix` semantics.
    static func stripBotPrefix(_ message: String) -> String {
        message.hasPrefix(botPrefix) ? String(message.dropFirst(botPrefix.count)) : message
    }

    /// True when the conversation should be treated as a support ticket ON THIS DEVICE.
    ///
    /// The check is deliberately SIDE-ASYMMETRIC, exactly as on Android: the two ends of the same
    /// conversation must answer this question from different evidence.
    ///
    /// - The user's device requires the support agent's key to actually be among the
    ///   participants. A display name is attacker-controlled, so trusting `"Support: …"` alone
    ///   would let any peer disguise itself as Zapp Support and get pinned to the top of the list.
    /// - The support agent's device cannot use that test at all: the SDK omits the LOCAL user's
    ///   own key from `participantIds`, so the agent never sees its own key there. It falls back
    ///   to the display-name prefix, which the ticket creator put on the wire with the invite.
    ///
    /// Which branch runs is decided by comparing the viewer's own identity against the support
    /// key — hence "which side am I on", not "does either party equal the support key".
    static func isSupportConversation(
        displayName: String,
        participantIds: [String],
        localPublicKey: String?
    ) -> Bool {
        let viewerIsSupportAgent = localPublicKey == supportPublicKey

        return viewerIsSupportAgent
            ? displayName.hasPrefix(displayNamePrefix)
            : participantIds.contains(supportPublicKey)
    }

    static func isSupportConversation(_ conversation: ZMConversation, localPublicKey: String?) -> Bool {
        isSupportConversation(
            displayName: conversation.displayName,
            participantIds: conversation.participantIds,
            localPublicKey: localPublicKey
        )
    }
}

// MARK: - Message mapping

/// A support-chat message as the screen renders it.
///
/// `origin` is deliberately decoupled from `isFromMe`: the user's OWN device posts the `[Zapp]:`
/// greeting and the leave notice, and both must read as system messages rather than as something
/// the user typed. Mirrors Android's `SupportMessageOrigin`.
struct SupportMessage: Equatable, Identifiable, Sendable {
    enum Origin: Equatable, Sendable {
        /// Typed by the local user. Trailing-aligned.
        case user
        /// Sent by the remote support agent. Leading-aligned.
        case agent
        /// Automated `[Zapp]:` greeting/notice. Leading-aligned.
        case bot
    }

    let id: String
    let content: String
    let origin: Origin
    let timestamp: Date
    /// Kept so media and file messages can reuse the ordinary chat bubbles.
    let message: ZMMessage

    var isFromLocalUser: Bool { origin == .user }

    /// Maps a wire message for display, returning `nil` for protocol markers that must never be
    /// rendered (`[Category: …]`). Mirrors `ChatMessage.toSupportUiMessageOrNull()`.
    static func from(_ message: ZMMessage) -> SupportMessage? {
        guard !SupportChatConstants.isCategoryMarker(message.content) else { return nil }

        let isBotPrefixed = message.content.hasPrefix(SupportChatConstants.botPrefix)
        let origin: Origin

        if isBotPrefixed {
            origin = .bot
        } else if message.isFromMe {
            origin = .user
        } else {
            origin = .agent
        }

        return SupportMessage(
            id: message.id,
            content: SupportChatConstants.stripBotPrefix(message.content),
            origin: origin,
            timestamp: message.timestamp,
            message: message
        )
    }
}
