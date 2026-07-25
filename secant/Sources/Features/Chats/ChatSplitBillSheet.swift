//
//  ChatSplitBillSheet.swift
//  Zapp
//
//  Android's `view/SplitBillSheet.kt`: a total, an optional per-participant override of the
//  equal split, a memo, and a send that posts one payment request per share.
//
//  In a direct chat there is nothing to split, so the same sheet becomes "Request payment" for
//  the whole total — exactly the branch Android takes on `state.isGroup`.
//
//  Field styling follows the established Zapp form idiom (`ChatContactFormView`): section label,
//  `surfaceInput` box, sharp corners. The arithmetic lives in `ChatSplitBillStore`.
//

import ComposableArchitecture
import SwiftUI

struct ChatSplitBillSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let shareFieldWidth: CGFloat = 150
        static let unitSpacing: CGFloat = 8
    }

    @Perception.Bindable var store: StoreOf<ChatRoom>

    let split: ChatRoom.SplitBillState

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                    Text(
                        split.isGroup
                            ? String(localizable: .chatSplitTitleGroup)
                            : String(localizable: .chatSplitTitleDirect)
                    )
                    .zappFont(.sectionTitle, style: ZappColors.text)

                    totalField

                    if split.isGroup {
                        participants
                    }

                    memoField

                    ZappButton(
                        title: String(localizable: .chatSplitSendButton),
                        isEnabled: split.canSend(rate: rate)
                    ) {
                        store.send(.splitSendTapped)
                    }
                }
                .padding(.horizontal, Design.Spacing._3xl)
                .padding(.vertical, Design.Spacing._xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    private var rate: ChatFiatRate? { store.state.chatFiatRate }

    private var totalField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .chatSplitTotalLabel))

            HStack(spacing: Constants.unitSpacing) {
                TextField(
                    String(localizable: .chatSplitTotalPlaceholder),
                    text: Binding(
                        get: { split.totalText },
                        set: { store.send(.splitTotalChanged($0)) }
                    )
                )
                .zappFont(.body, style: ZappColors.text)
                .keyboardType(.decimalPad)

                unitLabel(canToggle: rate != nil)
            }
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))

            if let equivalent {
                Text(String(localizable: .chatSplitEquivalent(equivalent)))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }
        }
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            ZappSectionLabel(text: String(localizable: .chatSplitSharesLabel(String(split.divisor))))

            ForEach(split.participants) { participant in
                HStack(spacing: Design.Spacing._lg) {
                    Text(participant.displayName)
                        .zappFont(.body, style: ZappColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Constants.unitSpacing) {
                        TextField(
                            String(localizable: .chatSplitTotalPlaceholder),
                            text: Binding(
                                get: { split.displayedShare(for: participant) },
                                set: { store.send(.splitShareChanged(publicKey: participant.publicKey, text: $0)) }
                            )
                        )
                        .zappFont(.body, style: ZappColors.text)
                        .keyboardType(.decimalPad)

                        unitLabel(canToggle: false)
                    }
                    .padding(Design.Spacing._md)
                    .background(ZappColors.surfaceInput.color(colorScheme))
                    .frame(width: Constants.shareFieldWidth)
                }
            }
        }
    }

    private var memoField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            TextField(
                String(localizable: .chatSplitMemoPlaceholder),
                text: Binding(
                    get: { split.memoText },
                    set: { store.send(.splitMemoChanged($0)) }
                ),
                axis: .vertical
            )
            .zappFont(.body, style: ZappColors.text)
            .lineLimit(1...3)
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    /// Tapping the unit swaps the whole sheet between ZEC and fiat, the way Android's
    /// `UnitLabel` does. Only the total carries the toggle; the share rows just label.
    @ViewBuilder
    private func unitLabel(canToggle: Bool) -> some View {
        if canToggle {
            Button {
                store.send(.splitCurrencyToggled)
            } label: {
                Text(unit)
                    .zappFont(.caption, style: ZappColors.text)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .chatSplitCurrencyToggle))
        } else {
            Text(unit)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    private var unit: String {
        if split.isFiat, let rate {
            return rate.symbol
        }

        return String(localizable: .chatSplitZecSuffix)
    }

    /// The total restated in the other currency, so the user always sees both sides of the trade.
    private var equivalent: String? {
        guard let total = split.total, total > 0, let rate else { return nil }

        if split.isFiat {
            return "\(ChatAmountFormat.zec(ChatAmountFormat.roundedZec(rate.fiatToZec(total)))) "
                + String(localizable: .chatSplitZecSuffix)
        }

        return "\(rate.symbol)\(ChatAmountFormat.fiat(ChatAmountFormat.roundedFiat(rate.zecToFiat(total))))"
    }
}
