//
//  UsernameRules.swift
//  Zapp
//

import Foundation

/// Chat display-name rules, mirroring `UsernameRules.kt`. The create path and the restore path MUST
/// agree — a restored identity that round-trips across devices needs to land with a name the create
/// flow would have accepted, otherwise the two paths produce different on-disk shapes.
enum UsernameRules {
    static let minLength = 3
    static let maxLength = 20

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")

    /// Deliberate divergence from Android: Kotlin filters on `isLetterOrDigit()`, which admits
    /// non-ASCII letters, so "é" survives `sanitize` only for `isValid` to reject it. Filtering to
    /// ASCII here makes `sanitize` actually guarantee the character set `isValid` demands, which is
    /// the intent the Kotlin was reaching for.
    ///
    /// Capped at `maxLength` for the same reason: an uncapped field let a 21st character through,
    /// which silently disabled Continue with no hint why.
    static func sanitize(_ raw: String) -> String {
        String(raw.lowercased().filter { allowed.contains($0) }.prefix(maxLength))
    }

    static func isValid(_ name: String) -> Bool {
        (minLength...maxLength).contains(name.count) && name.allSatisfy { allowed.contains($0) }
    }
}
