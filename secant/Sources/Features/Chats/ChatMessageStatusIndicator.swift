//
//  ChatMessageStatusIndicator.swift
//  Zapp
//

import SwiftUI

/// Delivery state on an outgoing bubble, rendered as a typographic mark in the Swiss style (no SF
/// Symbols): a clock while queued locally, a single tick once the blind relay accepts the encrypted
/// block, a muted double tick once the recipient confirms delivery, and a highlighted double tick
/// once the peer has read it — matching `MessageStatusIndicator.kt` and the convention every other
/// messenger uses.
///
/// Colours are supplied by the caller because they depend on the bubble the mark sits in.
struct ChatMessageStatusIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Status: String, Equatable {
        case sending
        case queued
        case sent
        case delivered
        case read
        case failed

        /// A missing or unrecognized persisted status predates delivery tracking and is treated as
        /// sent. Live status ordering uses `exact(wire:)` so an unknown event cannot advance a row.
        init(wire: String?) {
            self = Self.exact(wire: wire) ?? .sent
        }

        static func exact(wire: String?) -> Self? {
            wire.flatMap(Self.init(rawValue:))
        }

        /// Reciprocity only changes what the user can see. Keep the underlying read state so
        /// turning receipts back on can reveal it without waiting for another SDK event.
        func visible(readReceiptsEnabled: Bool) -> Self {
            !readReceiptsEnabled && self == .read ? .delivered : self
        }

        var tickCount: Int {
            switch self {
            case .delivered, .read: return 2
            case .sending, .queued, .sent, .failed: return 1
            }
        }

        var usesHighlightedColor: Bool {
            self == .read
        }
    }

    private enum Constants {
        static let markWidth: CGFloat = 15
        static let tickOffset: CGFloat = 4
        static let size: CGFloat = 10
        static let sendingSize: CGFloat = 11
        static let lineHeight: CGFloat = 16
    }

    let status: Status
    let mutedColor: Color
    let readColor: Color

    var body: some View {
        ZStack {
            mark
                .id(status)
                .transition(.opacity)
        }
        // One width for every state, so the time beside it never shifts sideways as delivery
        // progresses — the mark turns in place.
        .frame(width: Constants.markWidth, alignment: .leading)
        .animation(ZappMotion.content, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var mark: some View {
        if status.tickCount > 1 {
            ZStack(alignment: .topLeading) {
                glyph
                glyph.offset(x: Constants.tickOffset)
            }
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Text(text)
            .zappFont(
                ZappTextStyle(weight: .black, size: size, lineHeight: Constants.lineHeight),
                color: color
            )
    }

    var text: String {
        switch status {
        case .sending: return "◌"
        case .queued: return "◷"
        case .sent, .delivered, .read: return "✓"
        case .failed: return "!"
        }
    }

    private var color: Color {
        switch status {
        case .read: return readColor
        case .failed: return ZappColors.danger.color(colorScheme)
        case .sending, .queued, .sent, .delivered: return mutedColor
        }
    }

    private var size: CGFloat {
        status == .sending ? Constants.sendingSize : Constants.size
    }

    var accessibilityLabel: String {
        switch status {
        case .sending: return String(localizable: .chatRoomStatusSending)
        case .queued: return String(localizable: .chatRoomStatusQueued)
        case .sent: return String(localizable: .chatRoomStatusSent)
        case .delivered: return String(localizable: .chatRoomStatusDelivered)
        case .read: return String(localizable: .chatRoomStatusRead)
        case .failed: return String(localizable: .chatRoomStatusFailed)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ChatMessageStatusIndicator(status: .sending, mutedColor: .gray, readColor: .black)
        ChatMessageStatusIndicator(status: .queued, mutedColor: .gray, readColor: .black)
        ChatMessageStatusIndicator(status: .sent, mutedColor: .gray, readColor: .black)
        ChatMessageStatusIndicator(status: .delivered, mutedColor: .gray, readColor: .black)
        ChatMessageStatusIndicator(status: .read, mutedColor: .gray, readColor: .black)
        ChatMessageStatusIndicator(status: .failed, mutedColor: .gray, readColor: .black)
    }
    .applyScreenBackground()
}
