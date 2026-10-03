// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

struct ZappCompactLedgerRow: Identifiable, Equatable {
    let label: String
    let value: String
    var isDanger = false
    var id: String { label }
}

/// P2P settlement summary, mirroring Android's `ZappSettlementLedger`: a bordered surface with a
/// 3pt rule down its leading edge, label/value rows and an optional notice block.
struct ZappCompactLedger: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let barWidth: CGFloat = 3
        static let padding: CGFloat = 14
        static let rowSpacing: CGFloat = 10
        static let valueGap: CGFloat = 12
        static let noticeTopGap: CGFloat = 2
        static let noticeHorizontalPadding: CGFloat = 12
        static let noticeVerticalPadding: CGFloat = 10
        static let valueStyle = ZappTextStyle(weight: .medium, size: 14, lineHeight: 20)
        static let noticeStyle = ZappTextStyle(weight: .medium, size: 12, lineHeight: 16)
    }

    let rows: [ZappCompactLedgerRow]
    var notice: String?
    /// Turns the rule and the notice red, for a settlement that needs the user's attention.
    var noticeIsDanger = false

    var body: some View {
        VStack(spacing: Constants.rowSpacing) {
            ForEach(rows) { row in
                HStack(alignment: .center, spacing: 0) {
                    Text(row.label)
                        .zappFont(.caption, style: ZappColors.textMuted)
                    Spacer(minLength: Constants.valueGap)
                    Text(row.value)
                        .zappFont(Constants.valueStyle, style: row.isDanger ? ZappColors.danger : ZappColors.text)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let notice {
                Text(notice)
                    .zappFont(Constants.noticeStyle, style: noticeIsDanger ? ZappColors.danger : ZappColors.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Constants.noticeHorizontalPadding)
                    .padding(.vertical, Constants.noticeVerticalPadding)
                    .background((noticeIsDanger ? ZappColors.dangerSoft : ZappColors.accentSoft).color(colorScheme))
                    .padding(.top, Constants.noticeTopGap)
            }
        }
        .padding(Constants.padding)
        .padding(.leading, Constants.barWidth)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill((noticeIsDanger ? ZappColors.danger : ZappColors.accent).color(colorScheme))
                .frame(width: Constants.barWidth)
        }
        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
    }
}

enum ZappOfframpStepStatus: Equatable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
}

struct ZappOfframpStepItem: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String?
    let status: ZappOfframpStepStatus
    /// Further caption lines under the label, as Android's `ZappStep.detailLines`.
    var detailLines: [String] = []
}

/// The vertical progress spine every multi-step money flow renders, as Android's `ZappStepList`:
/// 12pt square indicators (a 14pt ring while in progress) joined by a 2pt rule that fills as each
/// step completes.
struct ZappOfframpStepList: View {
    let items: [ZappOfframpStepItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ZappOfframpStepRow(item: item, isLast: index == items.count - 1)
            }
        }
        .animation(ZappMotion.content, value: items)
    }
}

private struct ZappOfframpStepRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let stepGap: CGFloat = 10
        static let detailGap: CGFloat = 2
        static let indicatorSize: CGFloat = 12
        static let progressSize: CGFloat = 14
        static let indicatorTopOffset: CGFloat = 4
        static let spineWidth: CGFloat = 2
        static let spineHeight: CGFloat = 22
        static let activeLabel = ZappTextStyle(weight: .semiBold, size: 14, lineHeight: 20)
    }

    let item: ZappOfframpStepItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Constants.stepGap) {
            VStack(spacing: 0) {
                indicator
                    .frame(width: Constants.progressSize, height: Constants.progressSize)
                    .padding(.top, Constants.indicatorTopOffset)

                if !isLast {
                    Rectangle()
                        .fill(item.status == .completed
                            ? ZappColors.accent.color(colorScheme)
                            : ZappColors.border.color(colorScheme))
                        .frame(width: Constants.spineWidth, height: Constants.spineHeight)
                }
            }

            VStack(alignment: .leading, spacing: Constants.detailGap) {
                Text(item.label)
                    .zappFont(item.status == .inProgress ? Constants.activeLabel : .body, style: labelColor)

                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    Text(detail).zappFont(.caption, style: ZappColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var details: [String] {
        (item.detail.map { [$0] } ?? []) + item.detailLines
    }

    @ViewBuilder
    private var indicator: some View {
        switch item.status {
        case .inProgress:
            ZappStepProgressRing()
                .transition(.opacity)
        case .completed:
            square(fill: ZappColors.accent.color(colorScheme), border: .accent)
                .transition(.opacity)
        case .failed:
            square(fill: ZappColors.danger.color(colorScheme), border: .danger)
        case .pending:
            square(fill: .clear, border: .border)
        }
    }

    private func square(fill: Color, border: ZappColors) -> some View {
        Rectangle()
            .fill(fill)
            .overlay(Rectangle().strokeBorder(border.color(colorScheme), lineWidth: 1))
            .frame(width: Constants.indicatorSize, height: Constants.indicatorSize)
    }

    private var labelColor: ZappColors {
        switch item.status {
        case .failed: return .danger
        case .pending: return .textMuted
        case .inProgress, .completed: return .text
        }
    }
}

/// Android's 14dp `CircularProgressIndicator` with a 2dp accent stroke. The system `ProgressView`
/// is a spoked wheel at this size, which reads as a different control.
private struct ZappStepProgressRing: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(ZappColors.accent.color(colorScheme), style: StrokeStyle(lineWidth: 2, lineCap: .square))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
            .accessibilityHidden(true)
    }
}
