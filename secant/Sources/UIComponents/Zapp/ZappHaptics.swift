//
//  ZappHaptics.swift
//  Zapp
//
//  Shared haptic vocabulary, the counterpart to `ZappMotion`: motion is what a micro-interaction
//  looks like, this is what it feels like.
//

import UIKit

/// The four pulses Zapp uses, mapped from the `HapticFeedbackType` constants Android fires so both
/// platforms punctuate the same moments.
///
/// | Android | Zapp | Fired at |
/// |---|---|---|
/// | `SegmentTick` | `selection` | tab switch (`ZappPillNavBar`) |
/// | `GestureThresholdActivate` | `selection` | swipe-to-leave arming (`ChatSwipeToRevealRow`) |
/// | `Confirm` | `success` | onboarding done screen |
/// | `Reject` | `error` | biometric enrollment failure |
/// | `LongPress` | `impact` | bubble reply |
/// | `Confirm` | `impact` | composer send — see `ZappHaptics.sendConfirm` |
///
/// Generators are made per call rather than cached: these fire on discrete user actions seconds
/// apart, so there is no burst to warm up for, and a cached generator would outlive the screen
/// that owns it.
@MainActor
enum ZappHaptics {
    /// Discrete choice among peers — a new tab, a gesture arming. Android's `SegmentTick` /
    /// `GestureThresholdActivate`.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A ceremony completed. Android's `Confirm`. Deliberately rare — it is the loudest pulse in
    /// the vocabulary, so it is reserved for once-per-flow moments, not per-action confirmations.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A rejection the user must notice. Android's `Reject`.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// A direct physical response to a deliberate action. Android's `LongPress`.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A burst of `selection` pulses, for a gesture that ticks continuously — chart scrubbing crosses
    /// dozens of points a second. The per-call rule above assumes seconds between pulses; here a cold
    /// generator would drop the first tick and lag the rest, so this one is held and kept warm for as
    /// long as the gesture's view is on screen. Android gets the same from `LocalHapticFeedback`.
    @MainActor
    final class SelectionTicker {
        private lazy var generator: UISelectionFeedbackGenerator = {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            return generator
        }()

        func tick() {
            generator.selectionChanged()
            generator.prepare()
        }
    }

    /// Sending a message.
    ///
    /// Android fires `Confirm` here (`ChatRoomInputRow.kt`), but its literal iOS translation — a
    /// `.success` notification — is a three-beat buzz, far too loud for something a user does
    /// dozens of times a minute. iOS messaging convention is a single light tap, so that is what
    /// this plays: same call site as Android, iOS-native weight, per the plan's "keep it subtle and
    /// iOS-idiomatic" rule.
    static func sendConfirm() {
        impact(.light)
    }
}
