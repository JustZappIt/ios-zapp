// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

struct ZappCompactLedgerRow: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}

/// Compact P2P settlement summary, mirroring Android's `ZappSettlementLedger` density.
struct ZappCompactLedger: View {
    @Environment(\.colorScheme) private var colorScheme

    let rows: [ZappCompactLedgerRow]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.label)
                        .zappFont(.caption, style: ZappColors.textMuted)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .zappFont(.caption, style: ZappColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: 2)
        }
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
}

/// Android-parity P2P progress list: 12–14pt indicators, a 2pt spine, and crisp state transitions.
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

    let item: ZappOfframpStepItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                indicator
                    .frame(width: 14, height: 14)
                    .padding(.top, 3)

                if !isLast {
                    Rectangle()
                        .fill(item.status == .completed
                            ? ZappColors.accent.color(colorScheme)
                            : ZappColors.border.color(colorScheme))
                        .frame(width: 2, height: 22)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .zappFont(item.status == .inProgress ? .rowTitle : .body, style: labelColor)

                if let detail = item.detail {
                    Text(detail).zappFont(.caption, style: ZappColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch item.status {
        case .inProgress:
            ProgressView()
                .controlSize(.mini)
                .tint(ZappColors.accent.color(colorScheme))
                .transition(.scale.combined(with: .opacity))
        case .completed:
            Asset.Assets.check.image
                .zImage(size: 10, style: ZappColors.onAccent)
                .frame(width: 12, height: 12)
                .background(ZappColors.accent.color(colorScheme))
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Rectangle()
                .fill(ZappColors.danger.color(colorScheme))
                .frame(width: 12, height: 12)
        case .pending:
            Rectangle()
                .stroke(ZappColors.border.color(colorScheme), lineWidth: 1)
                .frame(width: 12, height: 12)
        }
    }

    private var labelColor: ZappColors {
        switch item.status {
        case .failed: return .danger
        case .pending: return .textMuted
        case .inProgress, .completed: return .text
        }
    }
}
