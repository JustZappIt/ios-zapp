//
//  ChatNameResolution.swift
//  Zapp
//
//  Names are resolved at READ time. A local alias is never written back into the
//  conversation.
//
//  This is forced by the core, not a preference. `_sendDirectInvite` re-fires
//  every time either side opens the chat, and on receipt the invite
//  UNCONDITIONALLY overwrites the conversation's displayName with the peer's
//  self-declared name. So a locally-chosen name written into
//  `conversation.displayName` survives only until the peer next opens the chat.
//  Android tried "rename conversation on save contact" and deleted it. Do not
//  reintroduce it.
//
//  Precedence, DIRECT:  local alias -> the name that came over the wire -> first
//  8 hex of the peer's key.
//  GROUP: the wire name, always. A group name is shared state, not a personal
//  alias for one peer.
//

import Foundation
import ZappMessaging

extension ZMConversation {
    func resolvedDisplayName(_ contacts: ChatContacts) -> String {
        if type == .group {
            return displayName
        }

        // Scan every participant, not just the first: a conversation can carry our
        // own key at index 0, which would otherwise shadow the peer's alias.
        let alias = participantIds
            .lazy
            .compactMap { contacts.contact(for: $0)?.name }
            .first { !$0.isEmpty }

        if let alias {
            return alias
        }

        if !displayName.isEmpty {
            return displayName
        }

        return String(PublicKeyRules.sanitize(participantIds.first ?? "").prefix(8))
    }
}

extension ZMMessage {
    func resolvedSenderName(_ contacts: ChatContacts) -> String? {
        guard !isFromMe else { return senderName }

        if let alias = contacts.contact(for: senderId)?.name, !alias.isEmpty {
            return alias
        }

        return senderName
    }
}
