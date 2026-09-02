// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

/// One card in the deck: a peek strip while collapsed, the full card when brought to the front,
/// and a flip to its back for the long-form status.
struct GiftDeckCard: View {
    let item: GiftCardList.Item
    let isExpanded: Bool
    let isFlipped: Bool
    let onTap: () -> Void
    let onShare: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onCheck: () -> Void

    private static let corner: CGFloat = 16
    private static let peekHeight: CGFloat = 92

    private var stock: ZappGiftCardStock { item.tier.stock }

    var body: some View {
        Group {
            if isExpanded {
                expandedCard
            } else {
                peekStrip
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityLabel(
            isExpanded
                ? String(localizable: isFlipped ? .giftCardDeckShowFront : .giftCardDeckShowBack)
                : String(localizable: .giftCardDeckOpen)
        )
    }

    // MARK: - Peek

    /// Drawn as its own strip, not a clipped face, so the peek always shows the amount and never
    /// the fiat row beneath.
    private var peekStrip: some View {
        HStack(alignment: .center) {
            Text(item.amountText)
                .zappFont(.rowTitle, color: stock.figureInk ?? stock.ink)
            Spacer()
            statusPill
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: Self.peekHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(stock.face)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(stock.edge, lineWidth: stock.edgeWidth)
        )
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        ZStack {
            if isFlipped {
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                front
            }
        }
        .aspectRatio(giftCardAspect, contentMode: .fit)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(stock.face)
            GiftCardFlare(stock: stock, corner: Self.corner, isReverse: isFlipped)
                .clipShape(RoundedRectangle(cornerRadius: Self.corner))
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(stock.edge, lineWidth: stock.edgeWidth)
        }
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            HStack(alignment: .center) {
                Text(item.amountText)
                    .zappFont(.rowTitle, color: stock.figureInk ?? stock.ink)
                Spacer()
                statusPill
            }
            if let fiat = item.fiatText {
                Text(fiat)
                    .zappFont(.caption, color: stock.inkMuted)
            }
            if let message = item.message {
                Text(message)
                    .zappFont(.rowSubtitle, color: stock.inkMuted)
                    .lineLimit(2)
            }
            Spacer()
            HStack(alignment: .center, spacing: Design.Spacing._md) {
                if stock.showsWordmark {
                    Text(String(localizable: .giftCardDeckWordmark))
                        .zappFont(.eyebrow, color: stock.inkMuted)
                }
                if let created = item.createdAtText {
                    Text(String(localizable: .giftCardDeckCreated(created)))
                        .zappFont(.caption, color: stock.inkFaint)
                }
                Spacer()
                tools
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(alignment: .bottom) { scanTrack }
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            Text(String(localizable: .giftCardDeckDetails).uppercased())
                .zappFont(.eyebrow, color: stock.inkFaint)
            if let message = item.message {
                Text(message)
                    .zappFont(.rowSubtitle, color: stock.inkMuted)
                    .lineLimit(3)
            }
            if let created = item.createdAtText {
                Text(String(localizable: .giftCardDeckCreated(created)))
                    .zappFont(.caption, color: stock.inkFaint)
            }
            if let expiry = item.expiryText {
                Text(
                    item.isExpired
                        ? String(localizable: .giftCardListExpired(expiry))
                        : String(localizable: .giftCardListExpires(expiry))
                )
                .zappFont(.caption, color: stock.inkFaint)
            }
            if let checked = item.lastCheckedAtText {
                Text(String(localizable: .giftCardListCheckedUnclaimed(checked)))
                    .zappFont(.caption, color: stock.inkFaint)
                    .lineLimit(2)
            }
            Spacer()
            // A blocked check's reason outranks the status here.
            Text(longStatusText)
                .zappFont(.caption, color: stock.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: max(Self.corner - 8, 0))
                .strokeBorder(stock.ring ?? stock.edge, lineWidth: 0.8)
                .padding(18)
        )
    }

    private var longStatusText: String {
        if case .blocked(let reason) = item.check {
            switch reason {
            case .noTransaction: return String(localizable: .giftCardListCheckBlockedNoTx)
            case .anotherRunning: return String(localizable: .giftCardListCheckBlockedBusy)
            }
        }
        switch item.status {
        case .unfunded: return String(localizable: .giftCardListStatusUnfunded)
        case .retryable: return String(localizable: .giftCardListStatusRetryable)
        case .unresolved: return String(localizable: .giftCardListStatusUnresolved)
        case .submitted: return String(localizable: .giftCardListStatusSubmitted)
        case .funded: return String(localizable: .giftCardListStatusFunded)
        case .shared: return String(localizable: .giftCardListStatusShared)
        case .claimed: return String(localizable: .giftCardListStatusClaimed)
        }
    }

    // MARK: - Furniture

    /// Capsule on purpose: the pill is the card's own furniture, exempt from the sharp-corner
    /// rule the way the card's corners are.
    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.status == .claimed ? stock.inkFaint : ZappGiftCardStocks.liveMark)
                .frame(width: 6, height: 6)
            Text(chipText)
                .zappFont(.chip, color: stock.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(stock.ink.opacity(0.09)))
    }

    private var chipText: String {
        if case .running(let fraction) = item.check {
            if let fraction {
                return String(localizable: .giftCardChipCheckingProgress(Int(fraction * 100)))
            }
            return String(localizable: .giftCardChipChecking)
        }
        switch item.status {
        case .unfunded: return String(localizable: .giftCardChipUnfunded)
        case .retryable: return String(localizable: .giftCardChipRetryable)
        case .unresolved: return String(localizable: .giftCardChipUnresolved)
        case .submitted: return String(localizable: .giftCardChipSubmitted)
        case .funded: return String(localizable: .giftCardChipFunded)
        case .shared:
            if item.isLastCheckRecent { return String(localizable: .giftCardChipShared) }
            if item.lastCheckedAtText != nil { return String(localizable: .giftCardChipSharedStale) }
            return String(localizable: .giftCardChipSharedUnchecked)
        case .claimed: return String(localizable: .giftCardChipClaimed)
        }
    }

    private var tools: some View {
        HStack(spacing: Design.Spacing._sm) {
            if item.canHandOff {
                tool(icon: Asset.Assets.Icons.share.image, label: String(localizable: .giftCardListShare), action: onShare)
                tool(icon: Asset.Assets.copy.image, label: String(localizable: .giftCardListShare), action: onCopy)
            }
            if item.funding == .ready {
                tool(
                    icon: Asset.Assets.Icons.refreshSingleCCW.image,
                    label: String(localizable: .giftCardListRetryFunding),
                    action: onRetry
                )
            } else if item.funding == .running {
                ProgressView()
                    .frame(width: 44, height: 44)
            }
            switch item.check {
            case .ready:
                tool(icon: Asset.Assets.eyeOn.image, label: String(localizable: .giftCardListCheck), action: onCheck)
            case .running:
                tool(icon: Asset.Assets.eyeOff.image, label: String(localizable: .giftCardListCheckStop), action: onCheck)
            case .blocked, .hidden:
                EmptyView()
            }
        }
    }

    private func tool(icon: Image, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .zImage(width: 19, height: 19, color: stock.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(label)
    }

    /// A 3pt bar along the card's bottom edge while a check runs: fill by fraction, or a sweeping
    /// block before the SDK reports anything.
    @ViewBuilder
    private var scanTrack: some View {
        if case .running(let fraction) = item.check {
            Group {
                if let fraction {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(ZappGiftCardStocks.liveMark)
                            .frame(width: proxy.size.width * CGFloat(min(fraction, 1)))
                    }
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.4) / 1.4
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            let blockWidth = width * 0.3
                            Rectangle()
                                .fill(ZappGiftCardStocks.liveMark)
                                .frame(width: blockWidth)
                                .offset(x: (width + blockWidth) * phase - blockWidth)
                        }
                    }
                }
            }
            .frame(height: 3)
            .background(stock.core)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner))
            .padding(.horizontal, Self.corner)
        }
    }
}
