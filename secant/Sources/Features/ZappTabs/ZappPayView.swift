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
@preconcurrency import ZcashLightClientKit

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

                // Android makes the wallet-home error message a tap target onto the sync-error
                // sheet (`HomeVM.onWalletErrorMessageClick`); the progress row is the iOS row that
                // carries that message, so it is the tap target here. A healthy sync stays inert.
                ZappSyncProgressRow(
                    state: syncState,
                    percentage: store.smartBannerState.syncingPercentage,
                    errorMessage: store.smartBannerState.lastKnownErrorMessage
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isSyncErrorActionable else { return }

                    store.isZappSyncErrorSheetPresented = true
                }
                .accessibilityAddTraits(isSyncErrorActionable ? .isButton : [])

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
                    .zappScrollShadowSource()
                }
                .zappScrollEdges()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .overlay {
                speedDial()
            }
            .background {
                // `SmartBanner.reportTapped` fills `supportData` (or `messageToBeShared` when the
                // device has no mail account) and expects a view to be mounted that turns it into
                // a presented dialog. Upstream mounts these inside `SmartBannerView`, which the
                // Zapp tab shell never renders — so Contact Support silently did nothing here.
                supportDialogs()
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
            // Android auto-raises the sync-error sheet once per session; the reducer already
            // makes that decision (guarded by `isSyncTimedOutAutoAppeareDisabled`), so this
            // just follows it.
            .onChange(of: store.smartBannerState.isSyncTimedOutSheetPresented) { isRequested in
                if isRequested {
                    store.isZappSyncErrorSheetPresented = true
                }
            }
            .sheet(isPresented: $store.isZappSyncErrorSheetPresented) {
                syncErrorSheet()
            }
            .sheet(isPresented: $store.isZappPoolBalancesSheetPresented) {
                poolBalancesSheet()
            }
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
                confirmedBalance: confirmedBalance,
                shieldedBalance: store.walletBalancesState.shieldedWithPendingBalance,
                transparentBalance: store.walletBalancesState.transparentBalance,
                showsBreakdown: store.walletBalancesState.transparentBalance.amount > 0,
                canShield: store.walletBalancesState.transparentBalance >= store.walletBalancesState.autoShieldingThreshold,
                tokenName: tokenName,
                transactions: Array(store.transactionListState.transactions),
                showZecAsPrimary: showZecAsPrimary,
                onBalanceTapped: {
                    // Keep the balance reachable in privacy mode; the sheet masks every value.
                    store.send(.walletBalances(.balanceTapped))
                    store.isZappPoolBalancesSheetPresented = true
                },
                onToggleBalanceDisplay: { showZecAsPrimary.toggle() },
                onShieldTapped: { store.send(.smartBanner(.shieldFundsTapped)) }
            )
        }
    }

    /// Android's `GetBalanceHistoryUseCase`: total minus the shielded value that has not settled
    /// yet. It must be exactly that, because reconciliation compares it to the sum of settled
    /// transactions and hides the chart on any mismatch. Subtracting `shieldedWithPendingBalance -
    /// shieldedBalance` instead also removes `PoolBalance.lockedValue` — settled value the history
    /// does count — and a wallet carrying a migration lock could never reconcile.
    private var confirmedBalance: Zatoshi {
        store.walletBalancesState.totalBalance - store.walletBalancesState.pendingShieldedBalance
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
                .zappFont(.body, style: ZappColors.accentText)
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
            actions: speedDialActions,
            trailingPadding: Constants.fabTrailingPadding,
            bottomPadding: ZappNavBar.fabBottomPadding
        )
    }

    private var speedDialActions: [ZappSpeedDialAction] {
        var actions = [
            // Android's `PayActionSpeedDial` uses Storefront here, and the shopping bag is this
            // catalogue's nearest equivalent. It also removes a real ambiguity: the old `pay`
            // glyph is an arrow entering a circle, which read as "send" right beside Send.
            ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.shoppingBag.image,
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
                // The catalogue's exact counterpart to Android's `Icons.Default.SwapHoriz`.
                ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.switchHorizontal.image,
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
        ]
        if let baseURL = PartnerKeys.p2pOnrampBaseUrl,
           !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.insert(
                ZappSpeedDialAction(
                    icon: Asset.Assets.Icons.walletBuy.image,
                    label: String(localizable: .onrampSpeedDialBuy)
                ) {
                    store.send(.buyTapped)
                },
                at: 0
            )
        }
        return actions
    }
}

// MARK: - Pool balances surface

extension ZappPayView {
    @ViewBuilder func poolBalancesSheet() -> some View {
        WithPerceptionTracking {
            PoolBalancesSheet(
                store: store.scope(state: \.walletBalancesState, action: \.walletBalances),
                tokenName: tokenName,
                onDismiss: { store.isZappPoolBalancesSheetPresented = false }
            )
            // Android presents this as a wrap-content bottom sheet. `.large` pinned it open at
            // full height with a stranded button below the cards; the derived detent stops it at
            // its content, and `.large` stays available for larger type.
            .presentationDetents([.height(PoolBalancesSheet.detentHeight), .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Sync error surface

/// Android's sync-error remedies, mirroring `SyncErrorView.kt`. Kept in an extension so the tab's
/// main body stays about the tab's layout.
extension ZappPayView {
    /// Only a genuine failure gets a tap target — a mid-sync progress row has nothing to offer.
    var isSyncErrorActionable: Bool {
        syncState == .error || syncState == .offline
    }

    /// Every action closes the sheet first, then hands off, so the sheet is never still on screen
    /// when the destination it pushed appears. The `smartBanner` cases already clear the reducer's
    /// own flag (`SmartBannerStore` `serverSwitchRequested` / `torSettingsRequested` /
    /// `reportTapped`), which keeps the auto-raise mirror in sync.
    @ViewBuilder func syncErrorSheet() -> some View {
        WithPerceptionTracking {
            ZappSyncErrorSheet(
                // Offline is actionable but is not itself the previous synchronizer failure. Use
                // the generic copy/remedy there instead of leaking a stale error classification.
                errorMessage: syncState == .error ? store.smartBannerState.lastKnownErrorMessage : "",
                isIncompatibleServer:
                    syncState == .error && store.smartBannerState.lastKnownErrorIsIncompatibleServer,
                onTryAgain: {
                    store.isZappSyncErrorSheetPresented = false
                    // `Home.retrySync` restarts the synchronizer — the counterpart to Android's
                    // `synchronizerProvider.resetSynchronizer()`. It existed but nothing sent it.
                    store.send(.retrySync)
                },
                onSwitchServer: {
                    store.isZappSyncErrorSheetPresented = false
                    store.send(.smartBanner(.serverSwitchRequested))
                },
                onDisableTor: {
                    store.isZappSyncErrorSheetPresented = false
                    store.send(.smartBanner(.torSettingsRequested))
                },
                onContactSupport: {
                    store.isZappSyncErrorSheetPresented = false
                    store.send(.smartBanner(.reportTapped))
                }
            )
            .padding(.horizontal, Design.Spacing._3xl)
            .padding(.vertical, Design.Spacing._3xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZappColors.surface.color(colorScheme))
            .presentationDetents([.height(ZappSyncErrorSheet.detentHeight)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Mirrors `SmartBannerView`'s mail/share bridges. Both wrap UIKit presentations, so they are
    /// sized to zero and mounted off-layout exactly as upstream does.
    @ViewBuilder func supportDialogs() -> some View {
        WithPerceptionTracking {
            ZStack {
                if let supportData = store.smartBannerState.supportData {
                    UIMailDialogView(
                        supportData: supportData,
                        completion: { store.send(.smartBanner(.sendSupportMailFinished)) }
                    )
                    .frame(width: 0, height: 0)
                }

                if let message = store.smartBannerState.messageToBeShared {
                    UIShareDialogView(activityItems: [message]) {
                        store.send(.smartBanner(.shareFinished))
                    }
                    .frame(width: 0, height: 0)
                }
            }
        }
    }
}

#Preview {
    ZappPayView(store: Home.placeholder, tokenName: "ZEC")
}
