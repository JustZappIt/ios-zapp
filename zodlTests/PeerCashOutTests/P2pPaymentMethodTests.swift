// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Testing
@testable import zodl_internal

struct P2pPaymentMethodTests {
    @MainActor
    @Test func scanAndPayOutagePreservesSuccessfullyLoadedPeerDestinations() async {
        var state = P2pPaymentMethod.State.initial
        state.isPeerLoading = true
        state.isScanAndPayLoading = true
        state.isLoading = true
        let destination = PeerDestination(
            code: "revolut",
            currencies: [PeerFiatCurrency(code: "EUR", symbol: "€", precision: 2)],
            defaultCurrencyCodes: ["EUR"],
            validatesHandleLive: true,
            offersCurrencyChoice: false
        )
        let store = TestStore(initialState: state) { P2pPaymentMethod() }

        await store.send(.peerLoaded(destinations: [destination], isAvailable: true)) {
            $0.destinations = [destination]
            $0.isPeerAvailable = true
            $0.isPeerLoading = false
        }
        await store.send(.scanAndPayLoadFailed("p2p.me unavailable")) {
            $0.isScanAndPayLoading = false
            $0.isLoading = false
            $0.errorMessage = "p2p.me unavailable"
        }

        #expect(store.state.destinations == [destination])
        #expect(store.state.canSelectPeer)
    }
}
