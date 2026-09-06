// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// What the store made of an incoming link.
enum GiftLinkIntake: Equatable {
    /// Held. The token retrieves the link exactly once.
    case accepted(token: String)

    /// This exact link is already waiting, so the claim it would open is already on its way.
    case alreadyPending

    /// Oversized, or too many already waiting. There is nothing to open.
    case refused
}

/// Holds an incoming gift URI in memory between the deeplink that delivered it and the claim
/// screen that consumes it.
///
/// The link's fragment is the bearer secret, so it must not travel in navigation state: TCA state
/// is Equatable and gets dumped by debug tooling and test failures. Only the token travels, and it
/// means nothing on its own.
///
/// `take` leases the link until the claim screen calls `release`, preventing overlapping attempts.
final class PendingGiftLinkStore: @unchecked Sendable {
    /// Bounds the store, so a flood of links cannot grow it without limit.
    private static let maxPendingURIs = 16

    private let lock = NSLock()
    private var pending: [(token: String, raw: String)] = []
    private var active: Set<String> = []
    private var deferred: String?

    /// Registers `raw`. Never logs it, at any level.
    func put(_ raw: String) -> GiftLinkIntake {
        lock.lock()
        defer { lock.unlock() }
        return putLocked(raw)
    }

    /// Returns what `token` stands for and leases it until `release`.
    func take(_ token: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = pending.firstIndex(where: { $0.token == token }) else { return nil }
        let raw = pending.remove(at: index).raw
        active.insert(raw)
        return raw
    }

    func release(_ raw: String) {
        lock.lock()
        defer { lock.unlock() }
        active.remove(raw)
    }

    /// Holds `raw` across wallet creation, for a recipient who tapped a link before they had a
    /// wallet to claim it into. Their claim screen is about to be left behind, and its token is
    /// already spent, so this is the only thing standing between them and re-finding the message.
    func deferLink(_ raw: String) {
        lock.lock()
        defer { lock.unlock() }
        active.remove(raw)
        deferred = raw
    }

    /// Registers the deferred link for a fresh claim and returns its token, or nil if none is
    /// waiting. Nil also covers a link whose claim is already on its way in.
    func resumeDeferred() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let raw = deferred else { return nil }
        deferred = nil
        guard case .accepted(let token) = putLocked(raw) else { return nil }
        return token
    }

    private func putLocked(_ raw: String) -> GiftLinkIntake {
        if !GiftLinkCodec.isWithinSizeLimit(raw) {
            return .refused
        }
        if pending.contains(where: { $0.raw == raw }) || active.contains(raw) || raw == deferred {
            return .alreadyPending
        }
        if pending.count + active.count >= Self.maxPendingURIs {
            return .refused
        }
        let token = UUID().uuidString
        pending.append((token: token, raw: raw))
        return .accepted(token: token)
    }
}
