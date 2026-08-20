// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Testing
@testable import zodl_internal

@Suite(.serialized) @MainActor
struct OnrampDeliveryTests {
    @Test func escapedFailureUsesDurableCheckpointForRetrySafety() async {
        var state = Onramp.State.initial(currencyCode: "INR")
        state.page = .convertingToZec
        let checkpoint = OnrampCheckpointModel(
            id: "request-1",
            phase: .completed,
            orderID: "order-1",
            destination: .zcash,
            zecDelivery: OnrampDeliveryCheckpointModel(
                phase: .fundsOnBase,
                usdcMicros: "1190000",
                baseAccount: "0x1234",
                transferStarted: false,
                refundedUsdcMicros: nil,
                acceptedCostBasisPoints: 168,
                fundsLocation: .baseAccount
            )
        )
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.onramp.retryDelivery = { throw OnrampTestFailure() }
            $0.onramp.checkpoint = { checkpoint }
        }

        let failure = OnrampDeliveryModel(
            kind: .failed,
            stage: .fundsOnBase,
            inputUsdcMicros: "1190000",
            outputZec: nil,
            refundedUsdcMicros: nil,
            baseAccount: "0x1234",
            baseTransactionHash: nil,
            fundsLocation: .baseAccount,
            retryable: true,
            isTerminal: false,
            isSuccess: false
        )

        await store.send(.deliveryActionTapped)
        await store.receive(.deliveryFailed(failure)) {
            $0.delivery = failure
            $0.page = .deliveryNeedsAttention
            $0.errorMessage = Onramp.deliveryFailureMessage(.baseAccount)
        }
    }
}

private struct OnrampTestFailure: Error {}
