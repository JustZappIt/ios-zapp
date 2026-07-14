//
//  ZappMotion.swift
//  Zapp
//

import SwiftUI

/// Shared motion vocabulary for Zapp micro-interactions, mirroring `ZappMotion.kt`. Swiss design
/// language: short, crisp tweens — no springs, no overshoot.
enum ZappMotion {
    /// Small state changes: color swaps, press feedback, dot fills.
    static let state = curve(0.120)

    /// Content swaps: tab crossfade, error text reveal, step transitions.
    static let content = curve(0.200)

    /// Ceremonial reveals: seed unblur, success moments.
    static let reveal = curve(0.350)

    /// Full rejection-shake cycle.
    static let shake = curve(0.400)

    /// Compose's `FastOutSlowInEasing`.
    private static func curve(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: duration)
    }
}

/// Tactile press compression, mirroring `Modifier.pressScale`. Android layers this on top of a
/// ripple; iOS has no ripple, so the scale carries the press feedback on its own.
struct ZappPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(ZappMotion.state, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == ZappPressStyle {
    static var zappPress: ZappPressStyle { ZappPressStyle() }
}
