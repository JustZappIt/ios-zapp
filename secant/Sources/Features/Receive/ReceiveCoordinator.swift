//
//  ReceiveCoordinator.swift
//  modules
//
//  Created by Lukáš Korba on 2025-03-17.
//

import ComposableArchitecture

extension Receive {
    func coordinatorReduce() -> Reduce<Receive.State, Receive.Action> {
        Reduce { state, action in
            switch action {
                // MARK: Receive

            case let .addressDetailsRequest(address, maxPrivacy):
                var addressDetailsState = AddressDetails.State.initial
                addressDetailsState.address = address
                addressDetailsState.maxPrivacy = maxPrivacy
                if state.selectedWalletAccount?.vendor == .keystone {
                    addressDetailsState.addressTitle = maxPrivacy
                    ? String(localizable: .accountsKeystoneShieldedAddress)
                    : String(localizable: .accountsKeystoneTransparentAddress)
                } else {
                    addressDetailsState.addressTitle = maxPrivacy
                    ? String(localizable: .accountsZashiShieldedAddress)
                    : String(localizable: .accountsZashiTransparentAddress)
                }
                state.path.append(.addressDetails(addressDetailsState))
                return .none
                
                // MARK: - Request Zec

                // Presented, not pushed: the chain rises from the bottom the way Android's
                // `REQUEST` route does. See `ReceiveRequestFlow` for why.
            case let .requestTapped(address, maxPrivacy):
                state.memo = ""
                state.requestFlow = ReceiveRequestFlow.State(address: address, maxPrivacy: maxPrivacy)
                return .none

            case .requestFlow(.presented(.dismissRequested)):
                state.requestFlow = nil
                return .none

            default: return .none
            }
        }
    }
}
