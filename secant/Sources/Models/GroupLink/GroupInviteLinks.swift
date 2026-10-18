// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Recognises group invite links before anything reads them.
///
/// Two forms reach the app. The shared link, `https://join.justzappit.xyz/g/v1#<payload>`, and the
/// handoff the landing page opens, `xyz.justzappit.zapp://g/v1/<payload>`. Both carry a bearer
/// secret, so nothing here logs. The SDK does the real parsing; this only decides routing and trims
/// what another app may have appended. Mirrors Android's `GroupInviteLinks` decision for decision.
enum GroupInviteLinks {
    static let host = "join.justzappit.xyz"
    static let handoffScheme = "xyz.justzappit.zapp"
    static let handoffHost = "g"

    /// An honest link is under 200 characters. The bound keeps a hostile one out of storage.
    static let maxLength = 1024

    /// Routing only: does `raw` claim to be a group link? Says nothing about whether it reads.
    static func isGroupLink(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        if components.scheme?.lowercased() == "https" {
            return components.host?.lowercased() == host && components.percentEncodedPath.hasPrefix("/g/")
        }
        return components.scheme?.lowercased() == handoffScheme
            && components.host?.lowercased() == handoffHost
            && components.percentEncodedPath.hasPrefix("/")
    }

    /// The form worth keeping: the query dropped, since the secret is never in it and messaging
    /// apps append tracking parameters there. Nil for anything that is not a group link, or is too
    /// long to be an honest one.
    static func canonical(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maxLength, isGroupLink(trimmed) else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }
        components.percentEncodedQuery = nil
        if components.scheme?.lowercased() == "https" {
            // Rebuilt on the canonical host, as Android does, so the same link taken from the same
            // message is one string on both platforms whatever case the sender's app used.
            components.scheme = "https"
            components.host = host
        }
        guard let link = components.string, link.utf8.count <= maxLength else { return nil }
        return link
    }

    /// A link found in pasted text. Tolerates the whitespace, surrounding words and sentence
    /// punctuation a paste brings; a payload never starts or ends with any of those characters.
    static func fromPastedText(_ text: String) -> String? {
        let trimmed = CharacterSet(charactersIn: "<>()\"'.,")
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = String(word).trimmingCharacters(in: trimmed)
            if let link = canonical(candidate) { return link }
        }
        return nil
    }
}
