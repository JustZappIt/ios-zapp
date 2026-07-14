//
//  ChatRelativeTime.swift
//  Zapp
//

import Foundation

/// Chat-list time label, mirroring `RelativeTime.kt`: "now" / "5m" / "14:42" / "Tue" / "May 18".
enum ChatRelativeTime {
    private enum Elapsed {
        static let minute: TimeInterval = 60
        static let hour: TimeInterval = 3600
        static let day: TimeInterval = 86_400
        static let week: TimeInterval = 604_800
    }

    static func label(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)

        switch elapsed {
        case ..<Elapsed.minute:
            return String(localizable: .chatListTimeNow)
        case ..<Elapsed.hour:
            return "\(Int(elapsed / Elapsed.minute))m"
        case ..<Elapsed.day:
            return formatted(date, format: "HH:mm", locale: Locale(identifier: "en_US_POSIX"))
        case ..<Elapsed.week:
            return formatted(date, format: "EEE", locale: .current)
        default:
            return formatted(date, format: "MMM d", locale: .current)
        }
    }

    /// The clock label is POSIX-locale'd: a fixed "HH:mm" still renders 12-hour under a locale whose
    /// region prefers it. Weekday and month names stay on the device locale.
    private static func formatted(_ date: Date, format: String, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format

        return formatter.string(from: date)
    }
}
