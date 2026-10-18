//
//  ZappMigrationBanner.swift
//  Zapp
//
//  The Pay tab's Ironwood migration card, mirroring Android's `WalletMigrationBanner.kt`. It
//  renders the existing `SmartBanner` migration state (`priorityMigration` + its variant); the
//  copy stays the iOS variant copy, only the presentation is Android's bordered card.
//

import SwiftUI

struct ZappMigrationBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let ruleHeight: CGFloat = 3
        static let minVisibleFraction: CGFloat = 0.02
    }

    let variant: MigrationBannerVariant
    let onTap: () -> Void

    var body: some View {
        // Android makes the whole card the tap target as well as the "More" button. The
        // `.checkingStatus` door stays shut either way: `SmartBanner.smartBannerContentTapped`
        // guards it, so both entrances share one rule.
        Button(action: onTap) {
            ZappBorderedCard(variant: isAttention ? .danger : .standard) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            ZappSectionLabel(text: variant.title, color: isAttention ? .danger : .accentText)

                            Text(variant.info)
                                .zappFont(.rowTitle, style: ZappColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if variant.showsButton {
                            ZappCompactButton(title: variant.buttonLabel, action: onTap)
                        }
                    }

                    if let percent = variant.percent {
                        progressRule(percent: percent)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Android's ATTENTION phase: the run needs the user (plan update, expired transfers).
    private var isAttention: Bool {
        switch variant {
        case .updatePlan, .transfersExpired: return true
        default: return false
        }
    }

    private func progressRule(percent: Int) -> some View {
        let fraction = max(CGFloat(min(max(percent, 0), 100)) / 100, Constants.minVisibleFraction)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))

                Rectangle()
                    .fill((isAttention ? ZappColors.danger : ZappColors.accent).color(colorScheme))
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: Constants.ruleHeight)
    }
}

#Preview {
    VStack(spacing: 12) {
        ZappMigrationBanner(variant: .required) { }
        ZappMigrationBanner(variant: .inProgress(done: 2, total: 5, round: nil, totalRounds: nil)) { }
        ZappMigrationBanner(variant: .updatePlan) { }
    }
    .padding()
    .applyScreenBackground()
}
