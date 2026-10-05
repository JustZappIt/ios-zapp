// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// A gently curved check, ported point-for-point from Android's `drawTrimmedCheck`. Trim it to draw
/// it on; cubic segments and round caps keep it smooth at every point in the reveal.
struct ZappCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + side * x, y: rect.minY + side * y)
        }

        var path = Path()
        path.move(to: point(0.26, 0.51))
        path.addCurve(to: point(0.43, 0.64), control1: point(0.30, 0.55), control2: point(0.38, 0.64))
        path.addCurve(to: point(0.77, 0.31), control1: point(0.49, 0.64), control2: point(0.68, 0.36))
        return path
    }
}

/// The terminal-success moment for every money flow, as Android's `ZappSuccessBadge`: an accent
/// medallion settles while a complete outer ring resolves around it and the check draws on.
///
/// Round, unlike everything else in the house style. Android draws it with `drawCircle`, and the
/// medallion is the brand's one celebratory shape, so it is ported as drawn.
struct ZappSuccessBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
        static let canvasSize: CGFloat = 116
        static let markSize: CGFloat = 66
        static let markInitialScale: CGFloat = 0.88
        static let orbitSize: CGFloat = 88
        static let orbitStroke: CGFloat = 2.5
        static let orbitStartDegrees: Double = -72
        static let orbitDuration: TimeInterval = 0.48
        static let depthOffset: CGFloat = 3
        static let shadowOffset: CGFloat = 5
        static let shadowOpacity: CGFloat = 0.12
        static let checkSize: CGFloat = 56
        static let checkStrokeFraction: CGFloat = 0.085
    }

    @State private var markIn: CGFloat = 0
    @State private var checkTrim: CGFloat = 0
    @State private var orbit: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: orbit)
                .stroke(
                    ZappColors.accentShade.color(colorScheme),
                    style: StrokeStyle(lineWidth: Constants.orbitStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(Constants.orbitStartDegrees))
                .frame(width: Constants.orbitSize, height: Constants.orbitSize)

            Group {
                Circle()
                    .fill(ZappColors.shadow.color(colorScheme))
                    .opacity(Constants.shadowOpacity)
                    .offset(y: Constants.shadowOffset)
                Circle()
                    .fill(ZappColors.accentShade.color(colorScheme))
                    .offset(y: Constants.depthOffset)
                Circle()
                    .fill(ZappColors.accent.color(colorScheme))
            }
            .frame(width: Constants.markSize, height: Constants.markSize)
            .scaleEffect(Constants.markInitialScale + (1 - Constants.markInitialScale) * markIn)
            .opacity(markIn)

            ZappCheckShape()
                .trim(from: 0, to: checkTrim)
                .stroke(
                    ZappColors.onCompletion.color(colorScheme),
                    style: StrokeStyle(
                        lineWidth: Constants.checkSize * Constants.checkStrokeFraction,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: Constants.checkSize, height: Constants.checkSize)
        }
        .frame(width: Constants.canvasSize, height: Constants.canvasSize)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    /// Ring and medallion start together; the check draws on once the medallion has landed.
    private func play() {
        guard !reduceMotion else {
            orbit = 1
            markIn = 1
            checkTrim = 1
            return
        }
        withAnimation(ZappMotion.curve(Constants.orbitDuration)) { orbit = 1 }
        withAnimation(ZappMotion.content) { markIn = 1 }
        withAnimation(ZappMotion.reveal.delay(ZappMotion.contentDuration)) { checkTrim = 1 }
    }
}

/// The badge over a centred headline and explanation, as Android's `ZappSuccessHeader`. The copy
/// fades and rises into place just after the badge starts, so the mark leads.
struct ZappSuccessHeader: View {
    private enum Constants {
        static let headerGap: CGFloat = 18
        static let subtitleGap: CGFloat = 6
        static let subtitleWidthFraction: CGFloat = 0.86
        static let copyTravel: CGFloat = 8
        static let copyDelay: TimeInterval = 0.15
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    var subtitle: String?

    @State private var copyIn: CGFloat = 0

    var body: some View {
        VStack(spacing: Constants.headerGap) {
            ZappSuccessBadge()

            VStack(spacing: Constants.subtitleGap) {
                Text(title)
                    .zappFont(.display, style: ZappColors.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    ZappFractionWidth(fraction: Constants.subtitleWidthFraction) {
                        Text(subtitle)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .opacity(copyIn)
            .offset(y: Constants.copyTravel * (1 - copyIn))
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else {
                copyIn = 1
                return
            }
            withAnimation(ZappMotion.content.delay(Constants.copyDelay)) { copyIn = 1 }
        }
    }
}

/// Terminal-success CTA in the primary button's colours, as Android's `ZappDoneButton`: the check
/// beside the label draws on once as the button arrives, echoing the larger success mark.
struct ZappDoneButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
        static let minHeight: CGFloat = 52
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 14
        static let labelGap: CGFloat = 6
        static let checkSize: CGFloat = 16
        static let checkStrokeFraction: CGFloat = 0.12
    }

    let title: String
    let action: () -> Void

    @State private var checkTrim: CGFloat = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.labelGap) {
                ZappCheckShape()
                    .trim(from: 0, to: checkTrim)
                    .stroke(
                        ZappColors.onAccent.color(colorScheme),
                        style: StrokeStyle(
                            lineWidth: Constants.checkSize * Constants.checkStrokeFraction,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: Constants.checkSize, height: Constants.checkSize)

                Text(title)
                    .zappFont(.button, style: ZappColors.onAccent)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.minHeight)
            .background(ZappColors.accent.color(colorScheme))
        }
        // Android gives this a ripple and no press scale.
        .buttonStyle(.zappHighlight(tint: .onAccent))
        .accessibilityLabel(title)
        .onAppear {
            guard !reduceMotion else {
                checkTrim = 1
                return
            }
            withAnimation(ZappMotion.reveal) { checkTrim = 1 }
        }
    }
}

/// Proposes `fraction` of the offered width to its content and centres it — Compose's
/// `fillMaxWidth(fraction)`, which SwiftUI lacks before iOS 17.
private struct ZappFractionWidth: Layout {
    let fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = proposal.width.map { $0 * fraction }
        let size = subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let proposed = ProposedViewSize(width: bounds.width * fraction, height: bounds.height)
        subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: proposed)
    }
}

#Preview {
    VStack(spacing: 32) {
        ZappSuccessHeader(title: "Payment sent", subtitle: "The recipient has your ZEC.")
        ZappDoneButton(title: "Done") { }
    }
    .padding()
    .applyScreenBackground()
}
