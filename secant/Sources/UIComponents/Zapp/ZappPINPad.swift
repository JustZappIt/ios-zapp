//
//  ZappPINPad.swift
//  Zapp
//

import SwiftUI

/// Android's `PinComponents.kt` metrics.
enum ZappPINMetrics {
    static let keyHeight: CGFloat = 60
    static let dotSize: CGFloat = 14
    static let dotSpacing: CGFloat = 14
    /// A dot lands at this scale and settles to 1 as it fills.
    static let dotPopScale: CGFloat = 1.35
    /// How long a pressed key takes to fade back after release; the press itself is instant.
    static let keyReleaseFade: TimeInterval = 0.18
    /// Android's key face: `button` at 20sp Black.
    static let keyStyle = ZappTextStyle(weight: .black, size: 20, lineHeight: 26)
}

struct ZappPINDots: View {
    let filledCount: Int
    var hasError = false

    var body: some View {
        HStack(spacing: ZappPINMetrics.dotSpacing) {
            ForEach(0..<6, id: \.self) { index in
                ZappPINDot(isFilled: index < filledCount, hasError: hasError)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .appLockPINProgress(String(filledCount))))
    }
}

private struct ZappPINDot: View {
    @Environment(\.colorScheme) private var colorScheme

    let isFilled: Bool
    let hasError: Bool

    @State private var pops: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(color.color(colorScheme))
            .animation(ZappMotion.state, value: color)
            .frame(width: ZappPINMetrics.dotSize, height: ZappPINMetrics.dotSize)
            .modifier(ZappPINDotPop(pops: pops))
            .onChange(of: isFilled) { filled in
                guard filled else { return }
                withAnimation(ZappMotion.state) { pops += 1 }
            }
    }

    private var color: ZappColors {
        if hasError {
            return .danger
        }
        return isFilled ? .text : .border
    }
}

/// Snaps a dot to `dotPopScale` and eases it back to 1 each time `pops` steps up. The fractional
/// part of the animated value is the progress through the current pop, so it rests at scale 1.
private struct ZappPINDotPop: GeometryEffect {
    var pops: CGFloat

    var animatableData: CGFloat {
        get { pops }
        set { pops = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = pops - pops.rounded(.down)
        guard progress > 0 else { return ProjectionTransform() }
        let scale = ZappPINMetrics.dotPopScale - (ZappPINMetrics.dotPopScale - 1) * progress
        let transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

/// Phone-layout keypad as Android's `PinKeypad`: hairline-bordered transparent keys that invert
/// while pressed, with a key tick on every tap.
struct ZappPINPad: View {
    let isEnabled: Bool
    let onKey: (PINKey) -> Void

    @State private var keyTicker = ZappHaptics.KeyTicker()

    private let rows: [[PINKey?]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [nil, .digit(0), .delete]
    ]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        if let key {
                            Button {
                                keyTicker.tick()
                                onKey(key)
                            } label: {
                                Text(key.label)
                            }
                            .buttonStyle(ZappPINKeyStyle())
                            .disabled(!isEnabled)
                            .accessibilityLabel(key.accessibilityLabel)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: ZappPINMetrics.keyHeight)
                        }
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Android's key press: background to `text` and digit to `bg` the instant the finger lands, then
/// a 180ms fade back on release, so even the fastest tap flashes. No scale.
private struct ZappPINKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZappPINKeyBody(configuration: configuration)
    }
}

private struct ZappPINKeyBody: View {
    @Environment(\.colorScheme) private var colorScheme

    let configuration: ButtonStyleConfiguration

    var body: some View {
        let isPressed = configuration.isPressed
        configuration.label
            .zappFont(ZappPINMetrics.keyStyle, color: (isPressed ? ZappColors.bg : ZappColors.text).color(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: ZappPINMetrics.keyHeight)
            .background(isPressed ? ZappColors.text.color(colorScheme) : .clear)
            .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
            .contentShape(Rectangle())
            .animation(isPressed ? nil : .linear(duration: ZappPINMetrics.keyReleaseFade), value: isPressed)
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
