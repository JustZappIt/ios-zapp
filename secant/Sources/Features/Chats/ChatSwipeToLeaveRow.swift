//
//  ChatSwipeToLeaveRow.swift
//  Zapp
//

import SwiftUI
import UIKit
import ZappMessaging

private enum ChatSwipeConstants {
    /// Android's `revealThresholdPx`; also the commit point.
    static let revealThreshold: CGFloat = 80
    /// Android clamps the drag at twice the threshold.
    static let maxTranslation: CGFloat = revealThreshold * 2
    static let minimumDistance: CGFloat = 8
    static let labelTrailingPadding: CGFloat = 20
}

/// Swipe-left-to-reveal action row, mirroring `ChatListSwipeToLeave.kt`.
///
/// The chat list is a `ScrollView`/`LazyVStack`, not a `List`, so `.swipeActions` is unavailable.
/// Tracking only starts once the drag is unambiguously horizontal and leftwards, so the enclosing
/// scroll view keeps its vertical pan. From iOS 18 that takes a UIKit recognizer
/// (`ChatLeftSwipeRecognizer`): a `DragGesture` on the row claims the touch even through
/// `.simultaneousGesture`, and once rows fill the screen the list can no longer be scrolled.
struct ChatSwipeToRevealRow<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Rebuilds the revealed subtree when the row is reused for another conversation, the way
    /// Android re-keys its `pointerInput` on `item.id`.
    let identity: String
    let actionLabel: String
    let onAction: () -> Void
    /// Receives the row's tap handler already guarded against a just-completed swipe; the content
    /// must route its own tap through it rather than calling the store directly.
    @ViewBuilder let content: (@escaping () -> Void) -> Content
    let onTap: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var isTracking = false
    @State private var isArmed = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Flexible children, so the stack still sizes itself to `content`.
            Rectangle()
                .fill(ZappColors.danger.color(colorScheme))

            Text(actionLabel)
                .zappFont(Self.labelStyle, style: ZappColors.bg)
                .padding(.trailing, ChatSwipeConstants.labelTrailingPadding)

            content(guardedTap)
                .background(ZappColors.bg.color(colorScheme))
                .offset(x: offsetX)
        }
        .id(identity)
        .chatSwipeGesture(drag: swipeGesture, onChanged: trackSwipe, onEnded: endSwipe)
        .accessibilityAction(named: Text(actionLabel)) { onAction() }
    }

    /// Android draws the label with `typography.button` overridden to `FontWeight.Black`.
    private static var labelStyle: ZappTextStyle {
        ZappTextStyle(
            weight: .black,
            size: ZappTextStyle.button.size,
            lineHeight: ZappTextStyle.button.lineHeight,
            tracking: ZappTextStyle.button.tracking
        )
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: ChatSwipeConstants.minimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard isTracking || beginsSwipe(value) else { return }

                trackSwipe(value.translation.width)
            }
            .onEnded { _ in endSwipe(allowsCommit: true) }
    }

    private func trackSwipe(_ translation: CGFloat) {
        isTracking = true
        offsetX = min(0, max(-ChatSwipeConstants.maxTranslation, translation))
        updateArmedState()
    }

    /// `allowsCommit` is false when the system cancels the swipe, which only snaps the row back.
    private func endSwipe(allowsCommit: Bool) {
        guard isTracking else { return }

        let commits = allowsCommit && -offsetX >= ChatSwipeConstants.revealThreshold
        isArmed = false

        withAnimation(ZappMotion.content) {
            offsetX = 0
        }

        if commits {
            onAction()
        }

        // The row's own Button reports its tap on touch-up too, in the same run-loop turn
        // as this handler and in no guaranteed order. Clearing the flag one turn later
        // means `guardedTap` still sees the swipe and drops the tap — the analogue of
        // Android consuming the pointer change to cancel the clickable's tap tracking.
        // Without it, swiping a row would leave the conversation *and* open it.
        DispatchQueue.main.async { isTracking = false }
    }

    /// A swipe and a tap are the same touch, so a completed swipe must swallow the tap.
    private func guardedTap() {
        guard !isTracking else { return }

        onTap()
    }

    private func beginsSwipe(_ value: DragGesture.Value) -> Bool {
        value.translation.width < 0
            && abs(value.translation.width) > abs(value.translation.height)
    }

    /// Ticks once when the swipe arms the action, so the commit point is felt rather than watched.
    private func updateArmedState() {
        let armed = -offsetX >= ChatSwipeConstants.revealThreshold

        guard armed != isArmed else { return }

        isArmed = armed

        if armed {
            ZappHaptics.selection()
        }
    }
}

private extension View {
    @ViewBuilder
    func chatSwipeGesture(
        drag: some Gesture,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (Bool) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            gesture(ChatLeftSwipeRecognizer(onChanged: onChanged, onEnded: onEnded))
        } else {
            // Before iOS 18 a simultaneous drag leaves the scroll view's pan alone.
            simultaneousGesture(drag)
        }
    }
}

/// A pan that refuses to begin unless the touch is moving leftwards more than vertically, so every
/// other pan stays with the enclosing scroll view.
@available(iOS 18.0, *)
private struct ChatLeftSwipeRecognizer: UIGestureRecognizerRepresentable {
    /// Horizontal translation since the touch went down.
    let onChanged: (CGFloat) -> Void
    /// `true` when the finger lifted, `false` when the system cancelled the pan.
    let onEnded: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended:
            onEnded(true)
        case .cancelled, .failed:
            onEnded(false)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }

            let velocity = pan.velocity(in: pan.view)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
        }
    }
}

/// Chat-list specialization: keyed by conversation id, labelled "Leave".
struct ChatSwipeToLeaveRow<Content: View>: View {
    let conversation: ZMConversation
    let onLeave: () -> Void
    let onTap: () -> Void
    @ViewBuilder let content: (@escaping () -> Void) -> Content

    var body: some View {
        ChatSwipeToRevealRow(
            identity: conversation.id,
            actionLabel: String(localizable: .chatListLeaveAction),
            onAction: onLeave,
            content: content,
            onTap: onTap
        )
    }
}
