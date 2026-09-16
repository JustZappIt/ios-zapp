// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// `handsOffSignedPCZT` is the one seam Zapp adds to the upstream signing lane: past the firmware
/// gate, the proved and signed pair leaves through `pcztSigned` instead of being broadcast, and the
/// scan screen holds instead of a Sending screen being pushed. Off, the lane must still broadcast.
@Suite(.serialized) @MainActor struct KeystoneSigningLaneTests {
    private static func confirmationState() -> SendConfirmation.State {
        SendConfirmation.State(
            address: "ztestaddr",
            amount: Zatoshi(100_000),
            feeRequired: Zatoshi(10_000),
            message: "",
            proposal: .testOnlyFakeProposal(totalFee: 10_000)
        )
    }

    /// A PCZT stamped by a device on the minimum firmware, so the gate lets it through.
    private static func signedPczt() -> Pczt {
        var data = Data()
        data.append(contentsOf: Array("keystone:fw_version".utf8))
        data.append(contentsOf: [0x03, 13, 0, 1])
        return Pczt(data)
    }

    @Test func handsOffEmitsTheSignedPairAndNeverBroadcasts() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Self.confirmationState()
            state.handsOffSignedPCZT = true
            state.pcztWithProofs = Pczt([0x01])
            state.pcztWithSigs = Pczt([0x02])

            // `sdkSynchronizer` stays the unimplemented test value: any broadcast fails the test.
            let store = TestStore(initialState: state) {
                SendConfirmation()
            } withDependencies: {
                $0.mainQueue = .immediate
                $0.keystoneHandler.resetQRDecoder = { }
            }

            await store.send(.createTransactionFromPCZT)
            await store.receive(.pcztSigned(Pczt([0x01]), Pczt([0x02])))
            await store.finish()

            #expect(store.state.pcztWithSigs == Pczt([0x02]))
        }
    }

    @Test func withoutHandsOffTheLaneStillBroadcasts() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Self.confirmationState()
            state.pcztWithProofs = Pczt([0x01])
            state.pcztWithSigs = Pczt([0x02])
            let broadcasts = LockIsolated<[(Pczt, Pczt)]>([])

            let store = TestStore(initialState: state) {
                SendConfirmation()
            } withDependencies: {
                $0.mainQueue = .immediate
                $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
                $0.keystoneHandler.resetQRDecoder = { }
                $0.sdkSynchronizer = .noOp
                $0.sdkSynchronizer.createAndSubmitTransactionFromPCZT = { proofs, sigs in
                    broadcasts.withValue { $0.append((proofs, sigs)) }
                    return .success(txIds: ["ab"])
                }
            }
            store.exhaustivity = .off

            await store.send(.createTransactionFromPCZT)
            await store.receive(.sendDone)
            await store.finish()

            #expect(broadcasts.value.count == 1)
            #expect(broadcasts.value.first?.0 == Pczt([0x01]))
            #expect(broadcasts.value.first?.1 == Pczt([0x02]))
        }
    }

    @Test func handsOffHoldsTheScanInsteadOfPushingSending() async throws {
        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var initialState = SignWithKeystoneCoordFlow.State()
            initialState.sendConfirmationState.handsOffSignedPCZT = true
            var scanState = Scan.State.initial
            scanState.checkers = [.keystonePCZTScanChecker]
            initialState.path.append(.scan(scanState))
            let scanId = try #require(initialState.path.ids.last)

            let store = Store(initialState: initialState) {
                SignWithKeystoneCoordFlow()
            } withDependencies: {
                $0.mainQueue = .immediate
                $0.keystoneHandler.resetQRDecoder = { }
            }

            store.send(.path(.element(id: scanId, action: .scan(.foundPCZT(Self.signedPczt())))))

            await waitForLane { store.state.path[id: scanId, case: \.scan]?.isKeystoneSigningInProgress == true }

            #expect(store.state.path.count == 1)
            #expect(store.state.sendConfirmationState.pcztWithSigs == Self.signedPczt())
        }
    }

    @Test func withoutHandsOffTheScanPushesSending() async throws {
        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var initialState = SignWithKeystoneCoordFlow.State()
            var scanState = Scan.State.initial
            scanState.checkers = [.keystonePCZTScanChecker]
            initialState.path.append(.scan(scanState))
            let scanId = try #require(initialState.path.ids.last)

            let store = Store(initialState: initialState) {
                SignWithKeystoneCoordFlow()
            } withDependencies: {
                $0.mainQueue = .immediate
                $0.keystoneHandler.resetQRDecoder = { }
            }

            store.send(.path(.element(id: scanId, action: .scan(.foundPCZT(Self.signedPczt())))))

            await waitForLane { store.state.path.last?.is(\.sending) == true }

            #expect(store.state.path.count == 2)
            #expect(store.state.path[id: scanId, case: \.scan]?.isKeystoneSigningInProgress == false)
        }
    }
}

@MainActor
private func waitForLane(
    timeoutNanoseconds: UInt64 = 15_000_000_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(condition(), "Timed out waiting for the signing lane", sourceLocation: sourceLocation)
}
