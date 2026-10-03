//
//  ZappTabsStore.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

@Reducer
struct ZappTabs {
    enum Tab: Int, Equatable, CaseIterable, Identifiable {
        case pay
        case chats
        case you

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .pay: return String(localizable: .zappTabsPay)
            case .chats: return String(localizable: .zappTabsChats)
            case .you: return String(localizable: .zappTabsYou)
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .chats
        /// Where a tab that refuses to open — currently only Chats, when its terms are
        /// declined — sends the user back to. Chats is the launch tab, so Pay is the fallback.
        var previousTab: Tab = .pay
        var chatUnreadCount = 0

        /// Fed from Root's ZappMessagingState. The Chats tab shows the identity
        /// setup screen until this is true.
        var hasChatIdentity = false

        /// The chat identity's display name, for the You tab's profile card.
        var displayName: String?

        @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount? = nil

        /// The You tab's live row subtitles, as Android's `TabsVM` derives them. Re-read whenever
        /// the tab comes back into view, since the screens that change them are pushed over it.
        var localCurrency: UserPreferencesStorage.ExchangeRate?
        var p2pRail: P2pRail = .default
        /// nil until the rail's name and region resolve; the row shows its static subtitle meanwhile.
        var p2pRailSubtitle: String?

        /// Android's `TabsVM.hasPeerActivity`: an attempt not yet on the indexer, or an order still
        /// on offer. A cash-out can wait hours, so the Base account row says so.
        var hasPeerActivity: Bool { peerRuns.contains(where: \.isInFlight) || activePeerOrderCount > 0 }
        var peerRuns: [PeerRun] = []
        var activePeerOrderCount = 0

        /// Android hides the Wallet group until the wallet secret is ready.
        var hasWallet: Bool { selectedWalletAccount != nil }

        // Set by tab content when it pushes a fullscreen sub-screen that owns its
        // own bottom CTA, so the two don't overlap.
        var hideNavPill = false
    }

    enum Action: Equatable {
        case tabSelected(Tab)
        case fullscreenChanged(Bool)

        /// Sent when the You tab shows, and again by Root when a screen pushed over it closes.
        case youTabAppeared
        case youTabDisappeared
        case p2pRailSubtitleLoaded(P2pRail, String)
        case peerRunsChanged([PeerRun])
        case activePeerOrdersLoaded(Int)

        // Routed by RootCoordinator into Root's path overlays, the same way Home's
        // *Tapped actions are. The You tab stays navigation-agnostic.
        case allSettingsTapped
        case appLockTapped
        case chatContactsTapped
        case chatProfileTapped
        case chatSettingsTapped
        case chooseServerTapped
        #if VOTING_ENABLED
        case coinholderPollingTapped
        #endif
        case giftCardListTapped
        case localCurrencyTapped
        case onlineStatusTapped
        case portfolioChartTapped
        case p2pPaymentMethodTapped
        case p2pTransactionsTapped
        case readReceiptsTapped
        case torTapped
    }

    private enum CancelID {
        case peerRunner
        case peerOrders
        case p2pRailSubtitle
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.userStoredPreferences) var userStoredPreferences

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                guard tab != state.selectedTab else { return .none }

                state.previousTab = state.selectedTab
                state.selectedTab = tab
                return .none

            case .fullscreenChanged(let isFullscreen):
                state.hideNavPill = isFullscreen
                return .none

            case .youTabAppeared:
                guard state.selectedTab == .you else { return .none }

                state.localCurrency = userStoredPreferences.exchangeRate()
                let rail = userStoredPreferences.p2pRail() ?? .default
                if rail != state.p2pRail {
                    state.p2pRail = rail
                    state.p2pRailSubtitle = nil
                }
                return .merge(loadP2pRailSubtitle(rail), observePeerActivity())

            case .youTabDisappeared:
                return .merge(
                    .cancel(id: CancelID.peerRunner),
                    .cancel(id: CancelID.peerOrders),
                    .cancel(id: CancelID.p2pRailSubtitle)
                )

            case let .p2pRailSubtitleLoaded(rail, subtitle):
                // A late answer for a rail the user has since switched away from is stale.
                guard rail == state.p2pRail else { return .none }
                state.p2pRailSubtitle = subtitle
                return .none

            case .peerRunsChanged(let runs):
                let holding = runs.filter(\.holdsFunds).count
                let changed = holding != state.peerRuns.filter(\.holdsFunds).count
                state.peerRuns = runs
                // Android re-reads the chain whenever an attempt settles, which is when it gains
                // an order — an order that is broadcast but not yet indexed exists on no list.
                return changed ? loadActivePeerOrders() : .none

            case .activePeerOrdersLoaded(let count):
                state.activePeerOrderCount = count
                return .none

            case .allSettingsTapped, .appLockTapped, .chatContactsTapped, .chatProfileTapped, .chatSettingsTapped,
            .chooseServerTapped, .giftCardListTapped, .localCurrencyTapped, .onlineStatusTapped,
            .p2pPaymentMethodTapped, .p2pTransactionsTapped, .portfolioChartTapped, .readReceiptsTapped, .torTapped:
                return .none

            #if VOTING_ENABLED
            case .coinholderPollingTapped:
                return .none
            #endif
            }
        }
    }

    /// Android's `P2pRail.selectedSubtitle()`: "PIX - Brazil" for a scan-and-pay corridor,
    /// "Revolut - USD, EUR and 3 more" for a cash-out rail.
    private func loadP2pRailSubtitle(_ rail: P2pRail) -> Effect<Action> {
        .run { send in
            switch rail {
            case .scanAndPay(let currencyCode):
                guard let corridor = try await offramp.corridors().first(where: { $0.currencyCode == currencyCode }) else {
                    return
                }
                await send(.p2pRailSubtitleLoaded(
                    rail,
                    String(localizable: .settingsYouP2pRailSubtitle(corridor.paymentRail, corridor.countryName))
                ))

            case .peerCashOut(let destinationCode):
                guard let destination = try await peerCashOut.capabilities().destinations
                    .first(where: { $0.code == destinationCode }) else {
                    return
                }
                await send(.p2pRailSubtitleLoaded(
                    rail,
                    String(localizable: .settingsYouP2pRailSubtitle(
                        destination.displayName,
                        Self.currencySummary(destination)
                    ))
                ))
            }
        } catch: { _, _ in
            // The static subtitle stays: an outage is no reason to show a broken label.
        }
        .cancellable(id: CancelID.p2pRailSubtitle, cancelInFlight: true)
    }

    /// The rail's default currencies, then a count of the rest — Android's `currencySummary()`.
    static func currencySummary(_ destination: PeerDestination) -> String {
        let defaults = destination.defaultCurrencyCodes.isEmpty
            ? destination.currencyCodes
            : destination.defaultCurrencyCodes
        let shown = defaults.joined(separator: ", ")
        let remaining = destination.currencies.count - defaults.count
        return remaining > 0
            ? String(localizable: .settingsYouP2pRailCurrenciesMore(shown, remaining))
            : shown
    }

    private func observePeerActivity() -> Effect<Action> {
        guard peerCashOut.isConfigured() else { return .none }

        return .merge(
            .run { send in
                for await runnerState in try await peerCashOut.runnerState() {
                    await send(.peerRunsChanged(runnerState.runs))
                }
            } catch: { _, _ in
                // No Peer rails on this build; the row keeps its resting subtitle.
            }
            .cancellable(id: CancelID.peerRunner, cancelInFlight: true),
            loadActivePeerOrders()
        )
    }

    /// Filtered on the phase rather than the indexer's ACTIVE flag, as Android's
    /// `GetPeerActiveOrdersUseCase` is: a drained order stays ACTIVE on chain forever.
    private func loadActivePeerOrders() -> Effect<Action> {
        .run { send in
            let orders = try await peerCashOut.activeOrders()
            await send(.activePeerOrdersLoaded(orders.filter { !$0.isFinished }.count))
        } catch: { _, _ in
            // An unreadable chain is not evidence of activity.
        }
        .cancellable(id: CancelID.peerOrders, cancelInFlight: true)
    }
}

private extension PeerRun {
    /// Android's `isUnindexed && failure == null`. A failed attempt is never evicted, so counting
    /// it would leave the row claiming a cash-out is in progress for the rest of the session.
    var isInFlight: Bool { depositID == nil && failure == nil }
}

// MARK: Placeholders

extension ZappTabs.State {
    static var initial: ZappTabs.State {
        .init()
    }
}

extension ZappTabs {
    @MainActor
    static let initial = StoreOf<ZappTabs>(
        initialState: .initial
    ) {
        ZappTabs()
    }
}
