// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// A flat progress bar in the house style, as Android's `ZappProgressBar`: a hard-edged bordered
/// track, a big percentage headline, and a ten-part grid that makes the position readable at a
/// glance without reading the number at all.
///
/// Pass `fraction` nil while there is genuinely nothing to report — a scan that has not published a
/// figure yet — and the bar sweeps instead of sitting at a dishonest zero.
struct ZappProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let gap: CGFloat = 8
        static let trackHeight: CGFloat = 12
        static let ticks = 10
        static let headline = ZappTextStyle(weight: .semiBold, size: 32, lineHeight: 36, tracking: -1.0)
        static let emDash = "—"
    }

    let fraction: Double?
    var label: String?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.gap) {
            HStack(alignment: .lastTextBaseline) {
                // Muted while there is no figure, so the em dash reads as an absent value rather
                // than as another rule in the layout.
                Text(fraction.map { "\(Int(min(max($0, 0), 1) * 100))%" } ?? Constants.emDash)
                    .zappFont(Constants.headline, style: fraction == nil ? ZappColors.textSubtle : ZappColors.text)
                    .monospacedDigit()

                Spacer(minLength: Constants.gap)

                if let detail {
                    Text(detail)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .multilineTextAlignment(.trailing)
                }
            }

            track

            if let label {
                Text(label)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if let fraction {
                    Rectangle()
                        .fill(ZappColors.accent.color(colorScheme))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        .animation(ZappMotion.content, value: fraction)
                } else {
                    ZappProgressSweep(trackWidth: proxy.size.width)
                }

                ticks
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: Constants.trackHeight)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
        .clipped()
    }

    /// Nine hairlines cutting the track into tenths, in the page colour over the fill, so the bar
    /// reads as a measured scale rather than a blob.
    private var ticks: some View {
        HStack(spacing: 0) {
            ForEach(0..<Constants.ticks, id: \.self) { index in
                Spacer(minLength: 0)
                if index < Constants.ticks - 1 {
                    Rectangle()
                        .fill(ZappColors.bg.color(colorScheme))
                        .frame(width: 1)
                }
            }
        }
    }
}

/// A block sweeping the track for the stretch before a real figure exists. Constant speed, no
/// easing: an eased sweep reads as progress that speeds up and slows down.
private struct ZappProgressSweep: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let widthFraction: CGFloat = 0.28
    private static let duration: TimeInterval = 1.1

    let trackWidth: CGFloat

    @State private var isSweeping = false

    var body: some View {
        Rectangle()
            .fill(ZappColors.accent.color(colorScheme))
            .frame(width: trackWidth * Self.widthFraction)
            .offset(x: isSweeping ? trackWidth : -trackWidth * Self.widthFraction)
            .animation(.linear(duration: Self.duration).repeatForever(autoreverses: false), value: isSweeping)
            .onAppear { isSweeping = true }
    }
}

#Preview {
    VStack(spacing: 32) {
        ZappProgressBar(fraction: 0.42, label: "Confirming on the network", detail: "4 of 10")
        ZappProgressBar(fraction: nil, label: "Connecting")
    }
    .padding()
    .applyScreenBackground()
}
