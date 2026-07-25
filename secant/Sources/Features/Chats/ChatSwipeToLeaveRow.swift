//
//  ChatSwipeToLeaveRow.swift
//  Zapp
//

import SwiftUI
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
/// The gesture is attached with `.simultaneousGesture` — the same arrangement `ZashiBack`'s
/// edge-swipe uses — so the enclosing scroll view keeps its vertical pan; tracking only starts once
/// the drag is unambiguously horizontal and leftwards.
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
        .simultaneousGesture(swipeGesture)
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
                if !isTracking {
                    guard beginsSwipe(value) else { return }
                    isTracking = true
                }

                offsetX = min(0, max(-ChatSwipeConstants.maxTranslation, value.translation.width))
                updateArmedState()
            }
            .onEnded { _ in
                guard isTracking else { return }

                let commits = -offsetX >= ChatSwipeConstants.revealThreshold
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
            UISelectionFeedbackGenerator().selectionChanged()
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
