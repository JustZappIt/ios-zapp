// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// The presented, turning card — the create flow's live preview and the claim screen's subject.
///
/// One rule governs motion: the card turns by itself only while something is in flight (funding;
/// claiming); still otherwise, and a tap flips one face. It never reports progress — the bar below
/// does. The springs here are a documented exemption from the no-springs motion rule: the card is
/// an object, and Android's shipped podium settles and flips it with springs.
struct GiftCardPodium: View {
    let stock: ZappGiftCardStock
    let amountText: String
    var fiatText: String?
    /// Printed on the face under the amount. The claim screen prints fiat below the podium
    /// instead, so the face never carries it twice.
    var fiatOnFace = false
    var message: String?
    /// Uppercased caption in faint ink when there is no message — "A GIFT FOR YOU".
    var caption: String?
    var isTurning = false
    /// A change while still plays one full extra turn — the tier-crossing flourish.
    var flourishKey = 0

    private static let corner: CGFloat = 16
    private static let maxWidth: CGFloat = 420
    /// One turn every nine seconds while in flight.
    private static let turnDegreesPerSecond = 40.0
    private static let bobPeriod = 2.6
    private static let bobTravel: CGFloat = 6
    private static let slabThickness: CGFloat = 6

    @State private var restingAngle = 0.0
    @State private var turnStart: Date?
    @State private var lastObservedTurnAngle = 0.0
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: Design.Spacing._lg) {
            if isTurning {
                TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(turnStart ?? timeline.date)
                    let angle = (restingAngle + elapsed * Self.turnDegreesPerSecond)
                        .truncatingRemainder(dividingBy: 360)
                    let bob = sin(elapsed * 2 * .pi / Self.bobPeriod) * Self.bobTravel
                    slabCard(angle: angle, bob: bob)
                        .onChange(of: angle) { lastObservedTurnAngle = $0 }
                }
            } else {
                slabCard(angle: restingAngle, bob: 0)
                    .onTapGesture {
                        // Still cards flip on a tap; the nearest-face maths keeps a card that
                        // settled at 180 flipping back to 0 rather than winding on to 360.
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                            restingAngle = restingAngle < 90 ? 180 : 0
                        }
                    }
            }
        }
        .onAppear {
            hasAppeared = true
            if isTurning { turnStart = .now }
        }
        .onChange(of: isTurning) { turning in
            if turning {
                turnStart = .now
            } else {
                // Settle to the nearest face from wherever the turn left the card.
                let landed = lastObservedTurnAngle
                restingAngle = landed
                let nearest = (landed / 180).rounded() * 180
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                    restingAngle = nearest.truncatingRemainder(dividingBy: 360)
                }
            }
        }
        .onChange(of: flourishKey) { _ in
            guard hasAppeared, !isTurning else { return }
            let from = restingAngle
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) {
                restingAngle = from + 360
            }
            // Wind the angle back down so a screen left open does not accumulate turns.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    restingAngle = from.truncatingRemainder(dividingBy: 360)
                }
            }
        }
    }

    private func slabCard(angle: Double, bob: CGFloat) -> some View {
        let radians = angle * .pi / 180
        let showsBack = abs(cos(radians)) < 0 ? false : (angle.truncatingRemainder(dividingBy: 360) > 90
            && angle.truncatingRemainder(dividingBy: 360) < 270)
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                // Two projected ground shadows that narrow as the card goes edge-on, and do NOT
                // bob with the card — that separation is what sells the float.
                let squeeze = abs(cos(radians))
                Ellipse()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: width * 0.82 * max(squeeze, 0.08), height: 16)
                    .blur(radius: 14)
                    .offset(y: width / giftCardAspect / 2 + 24)
                Ellipse()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: width * 0.6 * max(squeeze, 0.06), height: 8)
                    .blur(radius: 5)
                    .offset(y: width / giftCardAspect / 2 + 7)

                // A thin stack of core-coloured planes stands in for the slab's thickness.
                ForEach(0..<3, id: \.self) { plane in
                    let depth = CGFloat(plane - 1)
                    RoundedRectangle(cornerRadius: Self.corner)
                        .fill(stock.core)
                        .offset(x: sin(radians) * Self.slabThickness * depth / 2)
                        .rotation3DEffect(
                            .degrees(angle),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.6
                        )
                        .offset(y: bob)
                }

                face(showsBack: showsBack, radians: radians)
                    .rotation3DEffect(
                        .degrees(angle + (showsBack ? 180 : 0)),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.6
                    )
                    .offset(y: bob)
            }
            .frame(width: width, height: width / giftCardAspect)
        }
        .aspectRatio(giftCardAspect, contentMode: .fit)
        .frame(maxWidth: Self.maxWidth)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private func face(showsBack: Bool, radians: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(stock.face)
            GiftCardFlare(stock: stock, corner: Self.corner, isReverse: showsBack)
                .clipShape(RoundedRectangle(cornerRadius: Self.corner))
            if showsBack {
                backContent
            } else {
                frontContent
            }
            // The light catching the face: a horizontal gradient whose bright side swaps with the
            // turn and whose intensity rises as the face goes glancing.
            let glancing = abs(sin(radians))
            LinearGradient(
                colors: cos(radians) >= 0
                    ? [Color.white.opacity(0.10 * glancing), .clear, Color.black.opacity(0.16 * glancing)]
                    : [Color.black.opacity(0.16 * glancing), .clear, Color.white.opacity(0.10 * glancing)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.corner))
            .allowsHitTesting(false)
            // The sheen hairline near the top edge, which is what sells thickness.
            VStack {
                Rectangle()
                    .fill(stock.sheen)
                    .frame(height: 1)
                    .padding(.horizontal, Self.corner)
                    .padding(.top, 3)
                Spacer()
            }
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(stock.edge, lineWidth: stock.edgeWidth)
        }
        .aspectRatio(giftCardAspect, contentMode: .fit)
    }

    private var frontContent: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            if stock.showsWordmark {
                Text(String(localizable: .giftCardDeckWordmark))
                    .zappFont(.eyebrow, color: stock.inkMuted)
            }
            Spacer()
            Text(amountText)
                .zappFont(.display, color: stock.figureInk ?? stock.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if fiatOnFace, let fiatText {
                Text(fiatText)
                    .zappFont(.caption, color: stock.inkMuted)
            }
            if let message, !message.isEmpty {
                Text(message)
                    .zappFont(.rowSubtitle, color: stock.inkMuted)
                    .lineLimit(2)
            } else if let caption {
                Text(caption.uppercased())
                    .zappFont(.eyebrow, color: stock.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Design.Spacing._2xl)
    }

    private var backContent: some View {
        ZStack {
            if let ring = stock.ring {
                RoundedRectangle(cornerRadius: max(Self.corner - 8, 0))
                    .strokeBorder(ring, lineWidth: 0.8)
                    .padding(18)
            }
            if stock.showsWordmark {
                Text(String(localizable: .giftCardDeckWordmark))
                    .zappFont(.eyebrow, color: stock.inkFaint)
            }
        }
        // The back is rendered through an extra 180° turn, so its content needs the mirror fix.
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
