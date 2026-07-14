//
//  ZappToggle.swift
//  Zapp
//

import SwiftUI

struct ZappToggle: View {
    let isOn: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZappToggleIndicator(isOn: isOn)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(toggleAccessibilityValue(isOn))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

struct ZappToggleIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let width: CGFloat = 42
        static let height: CGFloat = 24
        static let knobSize: CGFloat = 20
        static let knobInset: CGFloat = 2
    }

    let isOn: Bool

    var body: some View {
        Rectangle()
            .fill((isOn ? ZappColors.accent : ZappColors.borderStrong).color(colorScheme))
            .frame(width: Constants.width, height: Constants.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(.white)
                    .frame(width: Constants.knobSize, height: Constants.knobSize)
                    .padding(.horizontal, Constants.knobInset)
            }
            .animation(ZappMotion.state, value: isOn)
            .accessibilityHidden(true)
    }
}

func toggleAccessibilityValue(_ isOn: Bool) -> String {
    String(localizable: isOn ? .zappToggleOn : .zappToggleOff)
}

#Preview {
    VStack(spacing: 12) {
        ZappToggle(isOn: true, accessibilityLabel: "Read receipts") { }
        ZappToggle(isOn: false, accessibilityLabel: "Online status") { }
    }
    .applyScreenBackground()
}
