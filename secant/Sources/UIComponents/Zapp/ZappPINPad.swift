//
//  ZappPINPad.swift
//  Zapp
//

import SwiftUI

struct ZappPINDots: View {
    @Environment(\.colorScheme)
    private var colorScheme

    let filledCount: Int
    var hasError = false

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<6, id: \.self) { index in
                Rectangle()
                    .fill(color(for: index))
                    .frame(width: 14, height: 14)
                    .scaleEffect(index < filledCount ? 1 : 0.86)
                    .animation(ZappMotion.state, value: filledCount)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .appLockPINProgress(String(filledCount))))
    }

    private func color(for index: Int) -> Color {
        if hasError {
            return ZappColors.danger.color(colorScheme)
        }
        return (index < filledCount ? ZappColors.text : ZappColors.border).color(colorScheme)
    }
}

struct ZappPINPad: View {
    @Environment(\.colorScheme)
    private var colorScheme

    let isEnabled: Bool
    let onKey: (PINKey) -> Void

    private let rows: [[PINKey?]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [nil, .digit(0), .delete]
    ]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        if let key {
                            Button {
                                onKey(key)
                            } label: {
                                Text(key.label)
                                    .zappFont(.pinKey, style: ZappColors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.zappPress)
                            .background(ZappColors.surface.color(colorScheme))
                            .overlay {
                                Rectangle()
                                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                            }
                            .disabled(!isEnabled)
                            .accessibilityLabel(key.accessibilityLabel)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                        }
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private extension PINKey {
    var label: String {
        switch self {
        case .delete:
            return "⌫"
        case let .digit(digit):
            return String(digit)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .delete:
            return String(localizable: .appLockPINDelete)
        case .digit:
            return label
        }
    }
}
