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
        var selected: P2pRail = .default
        var isLoading = false
        var errorMessage: String?

        var canSelectPeer: Bool { isPeerAvailable && isSoftwareWallet }
    }

    enum Action: Equatable {
        case onAppear
        case loaded(corridors: [OfframpCorridor], destinations: [PeerDestination], isPeerAvailable: Bool)
        case loadFailed(String)
        case railTapped(P2pRail)
        case backTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case close
        }
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.userStoredPreferences) var userStoredPreferences

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
                state.isSoftwareWallet = selectedAccount?.vendor == .zcash
                state.selected = userStoredPreferences.p2pRail() ?? .default
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    // The Peer capability read never throws on an unavailable build: it answers
                    // "not available" so the rails can be listed as such rather than vanishing.
                    let capabilities = try await peerCashOut.capabilities()
                    let corridors = try await offramp.corridors()
                    await send(.loaded(
                        corridors: corridors,
                        destinations: capabilities.destinations,
                        isPeerAvailable: capabilities.isAvailable
                    ))
                } catch: { error, send in
                    await send(.loadFailed(error.localizedDescription))
                }

            case let .loaded(corridors, destinations, isPeerAvailable):
                state.isLoading = false
                state.corridors = corridors
                state.destinations = destinations
                state.isPeerAvailable = isPeerAvailable
                return .none

            case let .loadFailed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none

            case let .railTapped(rail):
                guard rail.provider != .peer || state.canSelectPeer else { return .none }
                state.selected = rail
                // Written on the tap rather than behind a Save: there is nothing to review, and a
                // selection the user can see but the app has not stored is the confusing state.
                userStoredPreferences.setP2pRail(rail)
                return .none

            case .backTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }
}
