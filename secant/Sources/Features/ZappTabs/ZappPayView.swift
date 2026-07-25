//
//  ZappPayView.swift
//  Zapp
//
//  The Pay tab, mirroring `WalletHomeView.kt`. Upstream's `HomeView` stays byte-for-byte and
//  becomes dead-but-pristine, exactly as Android's `HomeView.kt` did: it reads the same
//  `StoreOf<Home>` and drives the same reducer, so the monthly upstream merge never sees this.
//

import ComposableArchitecture
import StoreKit
import SwiftUI

struct ZappPayView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let fabTrailingPadding: CGFloat = 18
        static let sectionLeadingPadding: CGFloat = 20
        static let cardHorizontalPadding: CGFloat = 18
        static let emptyBarWidth: CGFloat = 3
        static let emptyBarHeight: CGFloat = 20
    }

    @Perception.Bindable var store: StoreOf<Home>
    let tokenName: String

    /// Keeps the balance and activity rows on the same primary currency.
    /// Fiat leads by default (matches Android's `showZecAsPrimary = false`) when a rate exists.
    @State private var showZecAsPrimary = false

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .zappPayTitle)) {
                    ZappSyncChip(state: syncState)
                }

                ZappSyncProgressRow(
                    state: syncState,
                    percentage: store.smartBannerState.syncingPercentage,
                    errorMessage: store.smartBannerState.lastKnownErrorMessage
                )

                ScrollView {
                    VStack(spacing: 0) {
                        balanceCard()
                            .padding(.horizontal, Constants.cardHorizontalPadding)
                            .padding(.top, 14)
                            .padding(.bottom, 20)

                        ZappSmartActionStrip(
                            store: store.scope(state: \.smartBannerState, action: \.smartBanner)
                        )

                        ZappSectionLabel(text: String(localizable: .zappPayRecentActivity))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Constants.sectionLeadingPadding)
                            .padding(.bottom, 8)

                        activity()
                    }
                    .padding(.bottom, ZappNavBar.clearance)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .overlay {
                speedDial()
            }
            .onAppear {
                store.send(.onAppear)
                // The banner starts its streams on appear but does not kick the priority chain.
                // Trigger it here so the Android-parity Tor protection prompt is evaluated.
                store.send(.smartBanner(.evaluatePriority1))
            }
            .onChange(of: store.canRequestReview) { canRequestReview in
                if canRequestReview {
                    if let currentScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: currentScene)
                    }
                    store.send(.reviewRequestFinished)
                }
            }
            .onDisappear { store.send(.onDisappear) }
            .alert(
                store:
                    store.scope(
                        state: \.$alert,
                        action: \.alert
                    )
            )
        }
    }

    private var syncState: ZappSyncState {
        ZappSyncState(store.smartBannerState)
    }

    @ViewBuilder private func balanceCard() -> some View {
        WithPerceptionTracking {
            ZappBalanceCard(
                totalBalance: store.walletBalancesState.totalBalance,
                shieldedBalance: store.walletBalancesState.shieldedWithPendingBalance,
                transparentBalance: store.walletBalancesState.transparentBalance,
                showsBreakdown: store.walletBalancesState.transparentBalance.amount > 0,
                canShield: store.walletBalancesState.transparentBalance >= store.walletBalancesState.autoShieldingThreshold,
                tokenName: tokenName,
                transactions: Array(store.transactionListState.transactions),
                showZecAsPrimary: showZecAsPrimary,
                onToggleBalanceDisplay: { showZecAsPrimary.toggle() },
                onShieldTapped: { store.send(.smartBanner(.shieldFundsTapped)) }
            )
        }
    }

    @ViewBuilder private func activity() -> some View {
        WithPerceptionTracking {
            if store.transactionListState.transactions.isEmpty && !store.transactionListState.isInvalidated {
                emptyState()
            } else {
                ForEach(store.transactionListState.transactionListHomePage) { transaction in
                    WithPerceptionTracking {
                        ZappTransactionRow(
                            transaction: transaction,
                            tokenName: tokenName,
                            isUnread: TransactionList.isUnread(transaction),
                            isSwap: TransactionList.isSwap(transaction),
                            showZecAsPrimary: showZecAsPrimary,
                            divider: hasSeeAll || store.transactionListState.latestTransactionId != transaction.id
                        ) {
                            store.send(.transactionList(.transactionTapped(transaction.id)))
                        }
                        .onAppear {
                            if transaction.requiresAutoUpdate {
                                store.send(.transactionList(.transactionOnAppear(transaction.id)))
                            }
                        }
                    }
                }

                if hasSeeAll {
                    seeAllRow()
                }
            }
        }
    }

    private var hasSeeAll: Bool {
        store.transactionListState.transactions.count > TransactionList.Constants.homePageTransactionsCount
    }

    @ViewBuilder private func seeAllRow() -> some View {
        Button {
            store.send(.seeAllTransactionsTapped)
        } label: {
            Text(localizable: .zappPaySeeAll)
                .zappFont(.body, style: ZappColors.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func emptyState() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: Constants.emptyBarWidth, height: Constants.emptyBarHeight)
                .padding(.bottom, 14)

            Text(localizable: .zappPayEmptyTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.bottom, 4)

            Text(localizable: .zappPayEmptySubtitle)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    @ViewBuilder private func speedDial() -> some View {
        ZappSpeedDialFab(
            expandLabel: String(localizable: .zappPayFabExpand),
            collapseLabel: String(localizable: .zappPayFabCollapse),
            actions: [
                ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.pay.image,
                    label: String(localizable: .zappPayFabPay)
                ) {
                    store.send(.payWithNearTapped)
                },
                ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.sent.image,
                    label: String(localizable: .zappPayFabSend)
                ) {
                    store.send(.sendTapped)
                },
                ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.swap.image,
                    label: String(localizable: .zappPayFabSwap)
                ) {
                    store.send(.swapWithNearTapped)
                },
                ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.received.image,
                    label: String(localizable: .zappPayFabReceive)
                ) {
                    store.send(.receiveScreenRequested)
                }
            ],
            trailingPadding: Constants.fabTrailingPadding,
            bottomPadding: ZappNavBar.fabBottomPadding
        )
    }
}

#Preview {
    ZappPayView(store: Home.placeholder, tokenName: "ZEC")
}
