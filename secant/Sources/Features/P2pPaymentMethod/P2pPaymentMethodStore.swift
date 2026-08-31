// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// Choosing which P2P rail the Pay action opens.
///
/// A dedicated feature rather than another page inside the off-ramp: the two products do opposite
/// things — one pays a merchant, the other receives fiat — and a shared list that did not say so
/// would let someone pick "cash out" expecting "scan and pay".
@Reducer
struct P2pPaymentMethod {
    @ObservableState
    struct State: Equatable {
        static let initial = State()

        var corridors: [OfframpCorridor] = []
        var destinations: [PeerDestination] = []
        /// False on every build but Base mainnet, where the Peer rails do not exist at all.
        var isPeerAvailable = false
        /// Peer signs from the Base smart account this wallet derives, which a hardware wallet does
        /// not expose. The rails are shown as unavailable rather than hidden, so the absence is
        /// explained rather than mysterious.
        var isSoftwareWallet = true
        /// What the rows show. Only `saveTapped` writes it to preferences.
        var selected: P2pRail = .default
        /// What preferences hold, so the button knows whether anything changed.
        var saved: P2pRail = .default
        var isLoading = false
        var isPeerLoading = false
        var isScanAndPayLoading = false
        var errorMessage: String?

        var canSelectPeer: Bool { isPeerAvailable && isSoftwareWallet }

        var canSave: Bool { selected != saved }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case peerLoaded(destinations: [PeerDestination], isAvailable: Bool)
        case peerLoadFailed(String)
        case scanAndPayLoaded([OfframpCorridor])
        case scanAndPayLoadFailed(String)
        case railTapped(P2pRail)
        case saveTapped
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
        }
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.userStoredPreferences) var userStoredPreferences

    private enum CancelID {
        case peer
        case scanAndPay
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
                state.isSoftwareWallet = selectedAccount?.vendor == .zcash
                state.saved = userStoredPreferences.p2pRail() ?? .default
                state.selected = state.saved
                state.isLoading = true
                state.isPeerLoading = true
                state.isScanAndPayLoading = true
                state.errorMessage = nil
                return .merge(
                    .run { send in
                        // The Peer capability read never throws on an unavailable build: it answers
                        // "not available" so the rails can be listed as such rather than vanishing.
                        let capabilities = try await peerCashOut.capabilities()
                        await send(.peerLoaded(
                            destinations: capabilities.destinations,
                            isAvailable: capabilities.isAvailable
                        ))
                    } catch: { error, send in
                        await send(.peerLoadFailed(error.localizedDescription))
                    }
                    .cancellable(id: CancelID.peer, cancelInFlight: true),
                    .run { send in
                        await send(.scanAndPayLoaded(try await offramp.corridors()))
                    } catch: { error, send in
                        await send(.scanAndPayLoadFailed(error.localizedDescription))
                    }
                    .cancellable(id: CancelID.scanAndPay, cancelInFlight: true)
                )

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.peer),
                    .cancel(id: CancelID.scanAndPay)
                )

            case let .peerLoaded(destinations, isPeerAvailable):
                state.destinations = destinations
                state.isPeerAvailable = isPeerAvailable
                state.isPeerLoading = false
                state.isLoading = state.isScanAndPayLoading
                return .none

            case let .peerLoadFailed(message):
                state.isPeerLoading = false
                state.isLoading = state.isScanAndPayLoading
                state.errorMessage = message
                return .none

            case let .scanAndPayLoaded(corridors):
                state.corridors = corridors
                state.isScanAndPayLoading = false
                state.isLoading = state.isPeerLoading
                return .none

            case let .scanAndPayLoadFailed(message):
                state.isScanAndPayLoading = false
                state.isLoading = state.isPeerLoading
                state.errorMessage = message
                return .none

            case let .railTapped(rail):
                guard rail.provider != .peer || state.canSelectPeer else { return .none }
                state.selected = rail
                return .none

            case .saveTapped:
                guard state.canSave else { return .none }
                userStoredPreferences.setP2pRail(state.selected)
                state.saved = state.selected
                return .none

            case .backTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }
}
