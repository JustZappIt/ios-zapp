//
//  ZappToggle.swift
//  Zapp
//

import SwiftUI

struct ZappToggle: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let width: CGFloat = 42
        static let height: CGFloat = 24
        static let knobSize: CGFloat = 20
        static let knobInset: CGFloat = 2
    }

    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        ZappToggle(isOn: true) { }
        ZappToggle(isOn: false) { }
    }
    .applyScreenBackground()
}
