//
//  FiltersSheet.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-01-24.
//

import SwiftUI
import ComposableArchitecture

struct FilterView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 10
        static let iconSize: CGFloat = 16
        static let spacing: CGFloat = 6
    }

    let title: String
    let active: Bool
    let action: () -> Void

    init(
        title: String,
        active: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.spacing) {
                Text(title)
                    .zappFont(.button, style: active ? ZappColors.accentText : ZappColors.textMuted)
                    .lineLimit(1)

                if active {
                    Asset.Assets.Icons.xClose.image
                        .zImage(size: Constants.iconSize, style: ZappColors.accentText)
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .background(active
                ? ZappColors.accentSoft.color(colorScheme)
                : ZappColors.chipBg.color(colorScheme)
            )
            .overlay {
                if active {
                    Rectangle()
                        .strokeBorder(ZappColors.accent.color(colorScheme), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(title)
    }
}

extension TransactionsManagerView {
    @ViewBuilder func filtersContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .filterTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.top, 32)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    FilterView(title: String(localizable: .filterSent), active: store.isSentFilterActive) { store.send(.toggleFilter(.sent)) }
                    FilterView(title: String(localizable: .filterReceived), active: store.isReceivedFilterActive) { store.send(.toggleFilter(.received)) }
                    FilterView(title: String(localizable: .filterMemos), active: store.isMemosFilterActive) { store.send(.toggleFilter(.memos)) }
                }

                HStack(spacing: 8) {
                    FilterView(title: String(localizable: .filterNotes), active: store.isNotesFilterActive) { store.send(.toggleFilter(.notes)) }
                    FilterView(title: String(localizable: .filterBookmarked), active: store.isBookmarkedFilterActive) { store.send(.toggleFilter(.bookmarked)) }
                    FilterView(title: String(localizable: .filterSwap), active: store.isSwapFilterActive) { store.send(.toggleFilter(.swap)) }
                }
            }
            .padding(.bottom, 32)

            HStack(spacing: 12) {
                ZappButton(
                    title: String(localizable: .filterReset),
                    variant: .secondary
                ) {
                    store.send(.resetFiltersTapped)
                }

                ZappButton(title: String(localizable: .filterApply)) {
                    store.send(.applyFiltersTapped)
                }
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}
