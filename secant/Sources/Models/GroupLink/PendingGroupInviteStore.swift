// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Security

/// What the store made of an incoming invite link.
enum GroupInviteIntake: Equatable {
    /// Held. The token retrieves the link.
    case accepted(token: String)

    /// This exact link is already waiting, so the preview it would open is already on its way.
    case alreadyPending

    /// Not a group link, oversized, or too many already waiting. There is nothing to open.
    case refused
}

struct PendingGroupInvite: Codable, Equatable {
    let token: String
    let link: String
    let receivedAt: Date
}

/// Holds a tapped invite link until there is a wallet, a finished onboarding and a chat identity
/// to open it with.
///
/// The link is a bearer secret, so it is kept in the Keychain rather than in navigation state or
/// user defaults: TCA state is Equatable and gets dumped by debug tooling and test failures, and a
/// link in a defaults plist rides into every unencrypted backup. Only the token travels, and it
/// means nothing on its own.
///
/// An invite that nobody opened expires after seven days, matching Android, because a link kept
/// past the point where its owner would recognise it is a secret held for no one's benefit.
final class PendingGroupInviteStore: @unchecked Sendable {
    /// Bounds the store, so a flood of links cannot grow it without limit.
    static let maxPending = 4
    static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    /// Where the held invites live. Swapped for memory in tests.
    struct Persistence: Sendable {
        var load: @Sendable () -> Data?
        var save: @Sendable (Data) -> Void
        var clear: @Sendable () -> Void
    }

    private let lock = NSLock()
    private let persistence: Persistence
    private let now: @Sendable () -> Date

    init(persistence: Persistence, now: @escaping @Sendable () -> Date = { Date() }) {
        self.persistence = persistence
        self.now = now
    }

    /// Registers `raw`. Never logs it, at any level.
    func put(_ raw: String) -> GroupInviteIntake {
        guard let link = GroupInviteLinks.canonical(raw) else { return .refused }
        return lock.withLock {
            var invites = liveLocked()
            if invites.contains(where: { $0.link == link }) { return .alreadyPending }
            let token = UUID().uuidString
            // Newest first, so an older invite is the one dropped when the store is full.
            invites.insert(PendingGroupInvite(token: token, link: link, receivedAt: now()), at: 0)
            writeLocked(Array(invites.prefix(Self.maxPending)))
            return .accepted(token: token)
        }
    }

    /// What `token` stands for, or nil once it has lapsed or been used.
    func link(for token: String) -> String? {
        lock.withLock { liveLocked().first { $0.token == token }?.link }
    }

    /// The token of the most recent invite still waiting, for the resume after onboarding.
    func newestToken() -> String? {
        lock.withLock { liveLocked().first?.token }
    }

    func remove(token: String) {
        lock.withLock { writeLocked(liveLocked().filter { $0.token != token }) }
    }

    /// Called when the wallet is wiped: an invite is as personal as the chats it leads to.
    func clear() {
        lock.withLock { persistence.clear() }
    }

    private func liveLocked() -> [PendingGroupInvite] {
        guard let data = persistence.load(),
              let stored = try? JSONDecoder().decode([PendingGroupInvite].self, from: data) else {
            return []
        }
        let cutoff = now().addingTimeInterval(-Self.timeToLive)
        let live = stored.filter { $0.receivedAt > cutoff && GroupInviteLinks.canonical($0.link) != nil }
        if live.count != stored.count { writeLocked(live) }
        return live
    }

    private func writeLocked(_ invites: [PendingGroupInvite]) {
        guard !invites.isEmpty else {
            persistence.clear()
            return
        }
        guard let data = try? JSONEncoder().encode(invites) else { return }
        persistence.save(data)
    }
}

extension PendingGroupInviteStore.Persistence {
    /// The Keychain, which is where a bearer secret belongs: it survives the app being killed mid
    /// onboarding, and `ThisDeviceOnly` keeps it out of backups and off other devices.
    static func keychain(
        service: String = "xyz.justzappit.zapp.groupInvites",
        account: String = "pending"
    ) -> Self {
        @Sendable func baseQuery() -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
        }

        return Self(
            load: {
                var query = baseQuery()
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var result: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
                return result as? Data
            },
            save: { data in
                let query = baseQuery()
                let attributes: [String: Any] = [kSecValueData as String: data]
                if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }
                var insert = query
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(insert as CFDictionary, nil)
            },
            clear: {
                SecItemDelete(baseQuery() as CFDictionary)
            }
        )
    }

    /// Memory, for tests and previews.
    static func inMemory() -> Self {
        let box = MemoryBox()
        return Self(
            load: { box.value },
            save: { box.value = $0 },
            clear: { box.value = nil }
        )
    }
}

private final class MemoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    var value: Data? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
