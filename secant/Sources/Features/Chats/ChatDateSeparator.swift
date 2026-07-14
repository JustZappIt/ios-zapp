//
//  ChatDateSeparator.swift
//  Zapp
//

import SwiftUI

struct ChatDateSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String

    var body: some View {
        HStack(spacing: 0) {
            rule

            Text(label.uppercased())
                .zappFont(.eyebrow, style: ZappColors.textSubtle)
                .padding(.horizontal, Design.Spacing._lg)

            rule
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing._lg)
    }

    private var rule: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

extension ChatDateSeparator {
    nonisolated static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return String(localizable: .chatRoomDateToday)
        }

        if calendar.isDateInYesterday(date) {
            return String(localizable: .chatRoomDateYesterday)
        }

        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return date.formatted(.dateTime.weekday(.wide))
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

#Preview {
    VStack(spacing: 0) {
        ChatDateSeparator(label: ChatDateSeparator.label(for: Date()))

        ChatDateSeparator(label: ChatDateSeparator.label(for: Date(timeIntervalSinceNow: -86_400)))

        ChatDateSeparator(label: ChatDateSeparator.label(for: Date(timeIntervalSinceNow: -864_000)))
    }
    .applyScreenBackground()
}
