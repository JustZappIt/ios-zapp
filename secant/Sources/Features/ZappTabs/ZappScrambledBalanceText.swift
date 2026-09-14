//
//  ZappScrambledBalanceText.swift
//  Zapp
//

import SwiftUI

/// Android's eight-frame balance reveal. Currency marks and separators stay in place.
enum ZappBalanceScramble {
    static let frameCount = 8
    static let frameMilliseconds = 43
    private static let glyphs = Array("#%&?*+=§")

    static func frame(_ clearText: String, index: Int, revealing: Bool) -> String {
        let digitCount = clearText.filter(\.isNumber).count
        guard digitCount > 0 else { return clearText }

        let boundedFrame = min(max(index, 0), frameCount - 1)
        let transitionedDigits = revealing
            ? boundedFrame * digitCount / (frameCount - 1)
            : ((boundedFrame + 1) * digitCount + frameCount - 1) / frameCount
        var digitIndex = 0
        return String(clearText.enumerated().map { characterIndex, character in
            guard character.isNumber else { return character }

            let showClear = revealing ? digitIndex < transitionedDigits : digitIndex >= transitionedDigits
            digitIndex += 1
            return showClear ? character : glyphs[(characterIndex + boundedFrame * 3) % glyphs.count]
        })
    }
}

/// Only visibility changes scramble; initial rendering and live balance updates settle immediately.
/// The task identity cancels old frames on rapid taps, currency changes, and disappearance.
///
/// Deliberately not gated on `accessibilityReduceMotion` — swapping glyphs in place is not the
/// vestibular motion it suppresses, and gating it killed the effect outright. That setting still
/// suppresses the one real movement here, the numeric tween on a balance change.
struct ZappScrambledBalanceText: View {
    private struct Input: Equatable {
        let clear: String
        let hidden: String
        let isHidden: Bool
    }

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var previousHidden: Bool
    @State private var animationInput: Input?
    @State private var frame: Int?

    let clearText: String
    let hiddenText: String
    let isHidden: Bool

    init(clearText: String, hiddenText: String, isHidden: Bool) {
        self.clearText = clearText
        self.hiddenText = hiddenText
        self.isHidden = isHidden
        _previousHidden = State(initialValue: isHidden)
    }

    var body: some View {
        Text(displayedText)
            .contentTransition(.numericText())
            .animation(reduceMotion || isHidden ? nil : .easeOut(duration: 0.24), value: clearText)
            // Never announce transient glyphs or a partly masked amount as hidden content.
            .accessibilityLabel(settledText)
            .transaction {
                if isHidden || frame != nil || isTransitionPending { $0.animation = nil }
            }
            .task(id: input) {
                let visibilityChanged = previousHidden != isHidden
                previousHidden = isHidden
                frame = nil
                animationInput = input
                guard visibilityChanged else { return }

                for index in 0..<ZappBalanceScramble.frameCount {
                    guard !Task.isCancelled else { return }
                    frame = index
                    do {
                        try await Task.sleep(for: .milliseconds(ZappBalanceScramble.frameMilliseconds))
                    } catch {
                        return
                    }
                }
                frame = nil
            }
    }

    private var input: Input {
        Input(clear: clearText, hidden: hiddenText, isHidden: isHidden)
    }

    private var settledText: String { isHidden ? hiddenText : clearText }

    private var isTransitionPending: Bool { previousHidden != isHidden }

    private var displayedText: String {
        // `.task` starts a tick after the render that changed its id, so the flip's own frame has
        // no scramble frame yet; settling here makes the whole animation read as a snap.
        if isTransitionPending {
            return ZappBalanceScramble.frame(clearText, index: 0, revealing: !isHidden)
        }

        // New inputs must never reuse a frame from an old value or visibility state.
        guard animationInput == input, let frame else { return settledText }
        return ZappBalanceScramble.frame(clearText, index: frame, revealing: !isHidden)
    }
}
