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

    /// Presentation is owned locally rather than bound into `SmartBanner.State`: the reducer's
    /// `isSyncTimedOutSheetPresented` is the *request* to auto-raise (Android's once-per-session
    /// `hasSyncErrorBeenShown`), and mirroring it here keeps the upstream reducer unmutated from
    /// the view while still letting a tap open the sheet for errors the reducer never flagged.
    @State private var isSyncErrorSheetPresented = false

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

                    isSyncErrorSheetPresented = true
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
                    isSyncErrorSheetPresented = true
                }
            }
            .sheet(isPresented: $isSyncErrorSheetPresented) {
                syncErrorSheet()
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
                errorMessage: store.smartBannerState.lastKnownErrorMessage,
                onTryAgain: {
                    isSyncErrorSheetPresented = false
                    // `Home.retrySync` restarts the synchronizer — the counterpart to Android's
                    // `synchronizerProvider.resetSynchronizer()`. It existed but nothing sent it.
                    store.send(.retrySync)
                },
                onSwitchServer: {
                    isSyncErrorSheetPresented = false
                    store.send(.smartBanner(.serverSwitchRequested))
                },
                onDisableTor: {
                    isSyncErrorSheetPresented = false
                    store.send(.smartBanner(.torSettingsRequested))
                },
                onContactSupport: {
                    isSyncErrorSheetPresented = false
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
