//
//  ChatMessageStatusIndicator.swift
//  Zapp
//

import SwiftUI

/// Delivery state on an outgoing bubble, rendered as a typographic mark in the Swiss style (no SF
/// Symbols): a single tick once the message has left the device, a double tick once the peer has
/// read it.
///
/// Colours are supplied by the caller because they depend on the bubble the mark sits in.
struct ChatMessageStatusIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Status: Equatable {
        case sending
        case queued
        case sent
        case read
        case failed

        /// `nil` off the wire means the message left the device.
        init(wire: String?) {
            switch wire {
            case "sending": self = .sending
            case "queued": self = .queued
            case "read": self = .read
            case "failed": self = .failed
            default: self = .sent
            }
        }
    }

    private enum Constants {
        static let readWidth: CGFloat = 11
        static let readOffset: CGFloat = 4
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
        // One width for every state. The read mark is a double tick and is wider
        // than the others, so without this the time shifts sideways the moment a
        // message is read — the mark must turn in place, not nudge the row.
        .frame(width: Constants.readWidth, alignment: .leading)
        .animation(ZappMotion.content, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var mark: some View {
        if status == .read {
            ZStack(alignment: .topLeading) {
                glyph
                glyph.offset(x: Constants.readOffset)
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

    private var text: String {
        switch status {
        case .sending: return "◌"
        case .queued: return "◷"
        case .sent, .read: return "✓"
        case .failed: return "!"
        }
    }

    private var color: Color {
        switch status {
        case .read: return readColor
        case .failed: return ZappColors.danger.color(colorScheme)
        case .sending, .queued, .sent: return mutedColor
        }
    }

    private var size: CGFloat {
        status == .sending ? Constants.sendingSize : Constants.size
    }

    private var accessibilityLabel: String {
        switch status {
        case .sending: return String(localizable: .chatRoomStatusSending)
        case .queued: return String(localizable: .chatRoomStatusQueued)
        case .sent: return String(localizable: .chatRoomStatusSent)
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
        ChatMessageStatusIndicator(status: .read, mutedColor: .gray, readColor: .black)
        ChatMessageStatusIndicator(status: .failed, mutedColor: .gray, readColor: .black)
    }
    .applyScreenBackground()
}
