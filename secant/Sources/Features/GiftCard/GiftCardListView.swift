// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct GiftCardListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @Perception.Bindable var store: StoreOf<GiftCardList>

    /// The sender's place in the stack, not store state: which card is front, and whether it
    /// shows its back.
    @State private var selectedId: String?
    @State private var flippedId: String?

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .giftCardListTitle),
                    subtitle: String(localizable: .giftCardListSubtitle)
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                        banners
                        if store.items.isEmpty && !store.isCorrupted {
                            Text(String(localizable: .giftCardListEmpty))
                                .zappFont(.body, style: ZappColors.textMuted)
                                .padding(.top, Design.Spacing._2xl)
                        } else if !store.items.isEmpty {
                            Text(String(localizable: .giftCardListWarning))
                                .zappFont(.caption, style: ZappColors.textSubtle)
                            deck
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) { EmptyView() }
            }
            .applyScreenBackground()
            .sheet(
                isPresented: Binding(
                    get: { store.retryReview != nil },
                    set: { presented in
                        if !presented { store.send(.retryDismissTapped) }
                    }
                )
            ) { retrySheet }
            .background(shareMount)
            .onAppear { store.send(.onAppear) }
            .onChange(of: scenePhase) { phase in
                store.send(.foregroundChanged(phase == .active))
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        if store.isCorrupted {
            bannerText(String(localizable: .giftCardListCorrupted), style: .danger)
        }
        if let error = store.error {
            bannerText(errorText(error), style: .danger)
        }
        if let notice = store.notice {
            bannerText(noticeText(notice), style: .muted)
        }
    }

    private enum BannerStyle { case danger, muted }

    private func bannerText(_ text: String, style: BannerStyle) -> some View {
        Text(text)
            .zappFont(.caption, style: style == .danger ? ZappColors.danger : ZappColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                (style == .danger ? ZappColors.dangerSoft : ZappColors.surfaceAlt).color(colorScheme)
            )
    }

    private func errorText(_ error: GiftCardList.ListError) -> String {
        switch error {
        case .linkFailed: return String(localizable: .giftCardListErrorLink)
        case .shareFailed: return String(localizable: .giftCardListErrorShare)
        case .checkUnreachable: return String(localizable: .giftCardListErrorUnreachable)
        case .checkFailed: return String(localizable: .giftCardListErrorCheck)
        case .retryAuthenticationFailed: return String(localizable: .giftCardListErrorRetryAuth)
        case .retryInsufficientFunds: return String(localizable: .giftCardListErrorRetryFunds)
        case .retryFailed: return String(localizable: .giftCardListErrorRetry)
        case .retryUncertain: return String(localizable: .giftCardListErrorRetryUncertain)
        }
    }

    private func noticeText(_ notice: GiftCardList.ListNotice) -> String {
        switch notice {
        case .checkFundingPending: return String(localizable: .giftCardListNoticeFundingPending)
        case .retrySubmitted: return String(localizable: .giftCardListNoticeRetrySubmitted)
        }
    }

    // MARK: - The deck

    /// A vertical stack of cards overlapping by exactly the corner radius, back-to-front;
    /// collapsed cards show a peek strip, and tapping brings a card to the front.
    private var deck: some View {
        let selected = selectedId.flatMap { id in store.items.first { $0.id == id } } ?? store.items.first
        return VStack(spacing: -16) {
            ForEach(store.items) { item in
                let isSelected = item.id == selected?.id
                GiftDeckCard(
                    item: item,
                    isExpanded: isSelected,
                    isFlipped: isSelected && flippedId == item.id,
                    onTap: {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                            if isSelected {
                                flippedId = flippedId == item.id ? nil : item.id
                            } else {
                                selectedId = item.id
                                flippedId = nil
                            }
                        }
                    },
                    onShare: { store.send(.shareTapped(item.id)) },
                    onCopy: { store.send(.copyTapped(item.id)) },
                    onRetry: { store.send(.retryTapped(item.id)) },
                    onCheck: { store.send(.checkTapped(item.id)) }
                )
                // The card below an expanded one gets clearance so it laps onto empty space.
                .padding(.top, isSelected && item.id != store.items.first?.id ? 16 : 0)
                .padding(.bottom, isSelected ? 16 : 0)
                .zIndex(isSelected ? 1 : 0)
            }
        }
    }

    // MARK: - Retry sheet

    @ViewBuilder
    private var retrySheet: some View {
        if let review = store.retryReview {
            VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                Text(String(localizable: .giftCardRetryTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                Text(String(localizable: .giftCardRetryBody))
                    .zappFont(.body, style: ZappColors.textMuted)
                ZappBorderedCard {
                    VStack(spacing: Design.Spacing._lg) {
                        ZappSummaryRow(label: String(localizable: .giftCardReviewAmount), value: review.amountText)
                        ZappSummaryRow(label: String(localizable: .giftCardReviewReserve), value: review.claimFeeReserveText)
                        ZappSummaryRow(label: String(localizable: .giftCardReviewNetworkFee), value: review.networkFeeText)
                        ZappSummaryRow(label: String(localizable: .giftCardReviewTotal), value: review.totalText)
                        if let message = review.message {
                            ZappSummaryRow(label: String(localizable: .giftCardReviewMessageLabel), value: message)
                        }
                    }
                }
                ZappButton(title: String(localizable: .giftCardRetryConfirm)) {
                    store.send(.retryConfirmTapped)
                }
                ZappButton(title: String(localizable: .giftCardRetryCancel), variant: .secondary) {
                    store.send(.retryDismissTapped)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .applyScreenBackground()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var shareMount: some View {
        if let link = store.shareLink {
            UIShareDialogView(
                activityItems: [link],
                completion: {},
                onOutcome: { completed in store.send(.shareFinished(completed)) }
            )
        }
    }
}

#Preview {
    GiftCardListView(
        store: Store(initialState: GiftCardList.State()) {
            GiftCardList()
        }
    )
}
