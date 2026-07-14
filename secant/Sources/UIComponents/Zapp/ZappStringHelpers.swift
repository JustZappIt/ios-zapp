//
//  ZappStringHelpers.swift
//  Zapp
//

import Foundation

extension String {
    /// Up to two uppercase initials from a display name; falls back to the first two characters
    /// when the name has no word separators. Mirrors `initialsOf` in `ZappComponents.kt`.
    var zappInitials: String {
        let initials = split(whereSeparator: { " _-.".contains($0) })
            .prefix(2)
            .compactMap { $0.first?.uppercased() }
            .joined()

        return initials.isEmpty ? String(prefix(2)).uppercased() : initials
    }

    /// Shorten a long key / address to `head…tail`. Mirrors `ellipsizeAddress`.
    func zappEllipsized(head: Int = 10, tail: Int = 6) -> String {
        guard count > head + tail + 1 else { return self }

        return "\(prefix(head))…\(suffix(tail))"
    }
}
