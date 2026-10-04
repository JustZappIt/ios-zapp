//
//  SendCoordFlow+TopUp.swift
//  Zapp
//
//  Android's `TopUpVM`: the Send form's "Top Up" opens a source picker over the form, and the
//  picked source replaces it with that address's QR. Exchanges (Binance, Coinbase) can only send
//  to a transparent address; another Zcash wallet can send straight to the shielded address. The
//  QR is pushed on the send flow's own stack, so back returns to the form as it does on Android.
//

import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension SendCoordFlow {
    enum TopUpSource: Equatable {
        case exchange
        case wallet
    }

    func topUpReduce() -> Reduce<SendCoordFlow.State, SendCoordFlow.Action> {
        Reduce { state, action in
            switch action {
            case .topUpRequested:
                state.isTopUpPresented = true
                return .none

            case .topUpDismissed:
                state.isTopUpPresented = false
                return .none

            case .topUpSourcePicked(.exchange):
                state.isTopUpPresented = false
                let address = state.selectedWalletAccount?.transparentAddress
                    ?? String(localizable: .receiveErrorCantExtractTransparentAddress)
                state.path.append(.addressDetails(topUpAddressDetails(address: address, maxPrivacy: false, state: state)))
                return .none

            case .topUpSourcePicked(.wallet):
                state.isTopUpPresented = false
                guard state.selectedWalletAccount?.privateUA == nil,
                      let account = state.selectedWalletAccount else {
                    return .send(.topUpUnifiedAddressResolved(state.selectedWalletAccount?.privateUnifiedAddress))
                }
                // The shielded receive address is derived on demand, exactly as Home does before
                // opening Receive (`Home.receiveScreenRequested`).
                let receivers: Set<ReceiverType> = account.vendor == .keystone ? [.orchard] : [.sapling, .orchard]
                return .run { [sdkSynchronizer] send in
                    // Sent as its encoding: `UnifiedAddress` is not `Sendable`.
                    let privateUA = try? await sdkSynchronizer.getCustomUnifiedAddress(account.id, receivers)
                    await send(.topUpUnifiedAddressResolved(privateUA?.stringEncoded))
                }

            case .topUpUnifiedAddressResolved(let privateUA):
                let address = privateUA ?? String(localizable: .receiveErrorCantExtractUnifiedAddress)
                state.path.append(.addressDetails(topUpAddressDetails(address: address, maxPrivacy: true, state: state)))
                return .none

            default:
                return .none
            }
        }
    }

    /// The same address screen Receive pushes (`Receive.addressDetailsRequest`), titled the same way.
    private func topUpAddressDetails(address: String, maxPrivacy: Bool, state: State) -> AddressDetails.State {
        var addressDetailsState = AddressDetails.State.initial
        addressDetailsState.address = address.redacted
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
        return addressDetailsState
    }
}
