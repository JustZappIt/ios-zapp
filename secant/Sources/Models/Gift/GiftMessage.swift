// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Limits on the optional note a sender attaches to a card. Both bounds are part of the link
/// format shared with Android, and both are enforced as the sender types as well as on decode.
enum GiftMessage {
    /// Longest message, in grapheme clusters — what a reader would call "characters".
    static let maxGraphemes = 128

    /// Separate bound, because clusters say nothing about size: 128 emoji clear one and not the other.
    static let maxUTF8Bytes = 512

    /// Swift's `String.count` is already grapheme-clustered; never `utf16.count`, which makes one
    /// emoji 2 and a family emoji 7 or more.
    static func graphemeCount(_ value: String) -> Int {
        value.count
    }

    static func isWithinLimits(_ value: String) -> Bool {
        graphemeCount(value) <= maxGraphemes && value.utf8.count <= maxUTF8Bytes
    }
}
