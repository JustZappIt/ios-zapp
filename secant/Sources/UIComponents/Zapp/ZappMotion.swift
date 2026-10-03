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
    static let content = curve(contentDuration)
    static let contentDuration: TimeInterval = 0.200

    /// Ceremonial reveals: seed unblur, success moments.
    static let reveal = curve(0.350)

    /// Full rejection-shake cycle.
    static let shake = curve(0.400)

    /// Compose's `FastOutSlowInEasing`.
    static func curve(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: duration)
    }
}

/// Tactile press compression, mirroring `Modifier.pressScale`. Android applies it only to
/// `ZappButton` and `ZappFab`; everything else that is tappable takes `zappHighlight` instead.
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

/// Press feedback for rows, header titles, chips, segments, nav cells and icon buttons: a flat
/// wash over the control's own shape, standing in for the Material ripple Android draws there.
/// No scale — on Android whole rows never shrink, only `ZappButton` and `ZappFab` do.
struct ZappHighlightStyle: ButtonStyle {
    /// The ripple's color on Android: `text` on neutral surfaces, `onAccent` on accent fills.
    var tint: ZappColors = .text

    func makeBody(configuration: Configuration) -> some View {
        ZappHighlightBody(configuration: configuration, tint: tint)
    }
}

private struct ZappHighlightBody: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Material's pressed state-layer opacity.
    private static let pressedOpacity = 0.12

    let configuration: ButtonStyleConfiguration
    let tint: ZappColors

    var body: some View {
        configuration.label
            .overlay {
                Rectangle()
                    .fill(tint.color(colorScheme))
                    .opacity(configuration.isPressed ? Self.pressedOpacity : 0)
                    .allowsHitTesting(false)
            }
            .animation(ZappMotion.state, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == ZappHighlightStyle {
    static var zappHighlight: ZappHighlightStyle { ZappHighlightStyle() }

    static func zappHighlight(tint: ZappColors) -> ZappHighlightStyle {
        ZappHighlightStyle(tint: tint)
    }
}

/// Horizontal rejection shake, mirroring `Modifier.shake` (`ZappShake.kt`): 8pt out and back at
/// full, three-quarter and half amplitude on 50ms steps, settling by `ZappMotion.shake`'s 400ms.
/// Pair it with `ZappHaptics.error()` at the call site — the shake is the visual half of the cue.
private struct ZappShakeEffect: GeometryEffect {
    /// Completed shakes. Each run animates this up by one, and the fractional part is the progress
    /// through the current run, so a whole number always rests at zero offset.
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    private static let distance: CGFloat = 8
    private static let duration: Double = 0.4
    /// (time in ms, offset as a fraction of `distance`), as Android's keyframes.
    private static let keyframes: [(CGFloat, CGFloat)] = [
        (0, 0), (50, -1), (100, 1), (150, -0.75), (200, 0.75), (250, -0.5), (300, 0.5), (400, 0)
    ]

    static var animation: Animation { .linear(duration: duration) }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let milliseconds = (shakes - shakes.rounded(.down)) * Self.duration * 1000
        guard milliseconds > 0 else { return ProjectionTransform() }
        for (start, end) in zip(Self.keyframes, Self.keyframes.dropFirst()) where milliseconds <= end.0 {
            let fraction = (milliseconds - start.0) / (end.0 - start.0)
            let offset = start.1 + (end.1 - start.1) * fraction
            return ProjectionTransform(CGAffineTransform(translationX: offset * Self.distance, y: 0))
        }
        return ProjectionTransform()
    }
}

private struct ZappShakeModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let shouldShake: (Trigger) -> Bool

    @State private var shakes: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ZappShakeEffect(shakes: shakes))
            .onChange(of: trigger) { value in
                guard shouldShake(value) else { return }
                withAnimation(ZappShakeEffect.animation) {
                    shakes += 1
                }
            }
    }
}

extension View {
    /// Shakes each time `trigger` becomes true, as Android's `shake(trigger = hasError)`.
    func zappShake(trigger: Bool) -> some View {
        modifier(ZappShakeModifier(trigger: trigger) { $0 })
    }

    /// Shakes each time `trigger` changes to a non-nil value. Pass an attempt counter or the error
    /// itself when consecutive failures must each shake.
    func zappShake<Trigger: Equatable>(trigger: Trigger?) -> some View {
        modifier(ZappShakeModifier(trigger: trigger) { $0 != nil })
    }
}
