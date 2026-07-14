//
//  ChatContactsInterface.swift
//  Zapp
//

import ComposableArchitecture
import Foundation
import ZcashLightClientKit

extension DependencyValues {
    var chatContacts: ChatContactsClient {
        get { self[ChatContactsClient.self] }
        set { self[ChatContactsClient.self] = newValue }
    }
}

@DependencyClient
struct ChatContactsClient {
    var all: @Sendable (Account) throws -> ChatContacts = { _ in .empty }

    /// Upsert by public key. Marks the row saved, and preserves an existing
    /// `isBlocked` — saving a contact must never silently unblock them.
    var save: @Sendable (Account, ChatContact) throws -> ChatContacts = { _, _ in .empty }

    /// Deleting a *blocked* contact leaves a block-only row behind. Tidying your
    /// contact list must not double as an unblock.
    var delete: @Sendable (Account, _ publicKey: String) throws -> ChatContacts = { _, _ in .empty }

    /// Blocking a stranger creates a details-less row. Unblocking a row that was
    /// never saved removes it entirely, rather than leaving a ghost contact.
    var setBlocked: @Sendable (
        Account,
        _ publicKey: String,
        _ name: String,
        _ isBlocked: Bool
    ) throws -> ChatContacts = { _, _, _, _ in .empty }

    var resetAccount: @Sendable (Account) throws -> Void
}
