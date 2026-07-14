//
//  ZappScreenHeader.swift
//  Zapp
//

import SwiftUI

struct ZappScreenHeader<Left: View, Right: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappScreenHeaderConstants

    private let title: String
    private let subtitle: String?
    private let onTitleTap: (() -> Void)?
    private let left: Left
    private let right: Right

    init(
        title: String,
        subtitle: String? = nil,
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onTitleTap = onTitleTap
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(spacing: Constants.spacing) {
            left

            if let onTitleTap {
                Button(action: onTitleTap) { titles }
                    .buttonStyle(.zappPress)
            } else {
                titles
            }

            right
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surface.color(colorScheme))
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .zappFont(.screenTitle, style: ZappColors.text)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private enum ZappScreenHeaderConstants {
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 10
    static let spacing: CGFloat = 12
}

extension ZappScreenHeader where Left == EmptyView, Right == EmptyView {
    init(title: String, subtitle: String? = nil, onTitleTap: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, onTitleTap: onTitleTap) {
            EmptyView()
        } right: {
            EmptyView()
        }
    }
}

extension ZappScreenHeader where Left == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder right: () -> Right
    ) {
        self.init(title: title, subtitle: subtitle, onTitleTap: onTitleTap, left: { EmptyView() }, right: right)
    }
}

#Preview {
    VStack(spacing: 0) {
        ZappScreenHeader(title: "Chats", subtitle: "3 unread")

        ZappScreenHeader(title: "Settings") {
            ZappStatusChip(text: "Online", variant: .success, dotColor: .success)
        }

        Spacer()
    }
    .applyScreenBackground()
}
