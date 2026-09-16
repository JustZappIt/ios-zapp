// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// `Root` answers `keystoneSigning` requests with the shielding lane in hands-off mode. The arms
/// under test are the ones that differ from shielding: the caller's screen must survive a reject,
/// every way out of the lane must answer the waiting request exactly once, and a request the lane
/// cannot serve is refused without opening it.
///
/// Same shape as `RootTransactionsTests`: a plain `Store` with `LockIsolated` spies and polling,
/// `.serialized` because `Root.State` touches process-global `@Shared(.inMemory(...))` keys.
@Suite(.serialized) @MainActor struct RootKeystoneSigningTests {
    private typealias Completion = (id: UUID, result: Result<KeystoneSignedPczt, KeystoneSigningError>)

    private static func keystoneAccount(idByte: UInt8) -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: idByte, count: 16)),
                name: "Keystone",
                keySource: "keystone",
                seedFingerprint: [UInt8](repeating: 0x24, count: 32),
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
    }

    private static func request(for account: WalletAccount) -> KeystoneSigningRequest {
        KeystoneSigningRequest(id: UUID(), accountUUID: account.id, proposal: .testOnlyFakeProposal(totalFee: 0))
    }

    private func makeStore(
        selected: WalletAccount,
        completions: LockIsolated<[Completion]>,
        configure: (inout Root.State) -> Void = { _ in }
    ) -> StoreOf<Root> {
        var initialState = Root.State.initial
        initialState.$selectedWalletAccount.withLock { $0 = selected }
        initialState.path = .giftCard
        configure(&initialState)

        return Store(initialState: initialState) {
            Root()
        } withDependencies: {
            baseNoOpDependencies(&$0)
            $0.keystoneSigning = .noOp
            $0.keystoneSigning.complete = { id, result in
                completions.withValue { $0.append((id, result)) }
            }
        }
    }

    @Test func aRequestForTheSelectedAccountOpensTheLaneInHandsOffMode() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 90)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions)
            let request = Self.request(for: account)

            store.send(.keystoneSigningEvent(.requested(request)))

            await waitForRoot { store.state.signWithKeystoneCoordFlowBinding }
            let lane = store.state.signWithKeystoneCoordFlowState.sendConfirmationState
            #expect(store.state.pendingKeystoneSigningRequestId == request.id)
            #expect(lane.handsOffSignedPCZT)
            #expect(lane.proposal == request.proposal)
            #expect(store.state.path == .giftCard)
            #expect(completions.value.isEmpty)
        }
    }

    @Test func theSignedPairAnswersTheRequestAndClosesTheLane() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 91)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions)
            let request = Self.request(for: account)
            store.send(.keystoneSigningEvent(.requested(request)))
            await waitForRoot { store.state.signWithKeystoneCoordFlowBinding }

            store.send(.signWithKeystoneCoordFlow(.sendConfirmation(.pcztSigned(Pczt([0x01]), Pczt([0x02])))))

            await waitForRoot { !completions.value.isEmpty }
            #expect(completions.value.count == 1)
            #expect(completions.value.first?.id == request.id)
            #expect(completions.value.first?.result == .success(KeystoneSignedPczt(pcztWithProofs: Pczt([0x01]), pcztWithSigs: Pczt([0x02]))))
            #expect(!store.state.signWithKeystoneCoordFlowBinding)
            #expect(store.state.pendingKeystoneSigningRequestId == nil)
            #expect(store.state.path == .giftCard)
        }
    }

    @Test func rejectingAnswersRejectedAndKeepsTheCallerScreen() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 92)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions)
            let request = Self.request(for: account)
            store.send(.keystoneSigningEvent(.requested(request)))
            await waitForRoot { store.state.signWithKeystoneCoordFlowBinding }

            store.send(.signWithKeystoneCoordFlow(.sendConfirmation(.rejectTapped)))

            await waitForRoot { !completions.value.isEmpty }
            #expect(completions.value.first?.id == request.id)
            #expect(completions.value.first?.result == .failure(.rejected))
            #expect(!store.state.signWithKeystoneCoordFlowBinding)
            // Shielding's reject arm leaves for Home; a borrowed lane must not.
            #expect(store.state.path == .giftCard)
        }
    }

    @Test func swipingTheLaneAwayAnswersRejected() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 93)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions)
            let request = Self.request(for: account)
            store.send(.keystoneSigningEvent(.requested(request)))
            await waitForRoot { store.state.signWithKeystoneCoordFlowBinding }

            store.send(.binding(.set(\.signWithKeystoneCoordFlowBinding, false)))

            await waitForRoot { !completions.value.isEmpty }
            #expect(completions.value.first?.result == .failure(.rejected))
            #expect(store.state.pendingKeystoneSigningRequestId == nil)
        }
    }

    @Test func backingOutOfAPreSendingFailureAnswersFailed() async throws {
        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 94)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions)
            let request = Self.request(for: account)
            store.send(.keystoneSigningEvent(.requested(request)))
            await waitForRoot { store.state.signWithKeystoneCoordFlowBinding }
            store.send(.signWithKeystoneCoordFlow(.sendConfirmation(.pcztSendFailed(nil))))
            await waitForRoot { store.state.signWithKeystoneCoordFlowState.path.last?.is(\.preSendingFailure) == true }
            let failureId = try #require(store.state.signWithKeystoneCoordFlowState.path.ids.last)

            store.send(.signWithKeystoneCoordFlow(.path(.element(id: failureId, action: .preSendingFailure(.backFromPCZTFailureTapped)))))

            await waitForRoot { !completions.value.isEmpty }
            #expect(completions.value.first?.result == .failure(.failed))
            #expect(!store.state.signWithKeystoneCoordFlowBinding)
        }
    }

    @Test func aRequestForAnotherAccountIsRefusedWithoutOpeningTheLane() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: Self.keystoneAccount(idByte: 95), completions: completions)
            let request = Self.request(for: Self.keystoneAccount(idByte: 96))

            store.send(.keystoneSigningEvent(.requested(request)))

            await waitForRoot { !completions.value.isEmpty }
            #expect(completions.value.first?.id == request.id)
            #expect(completions.value.first?.result == .failure(.wrongAccount))
            #expect(!store.state.signWithKeystoneCoordFlowBinding)
            #expect(store.state.pendingKeystoneSigningRequestId == nil)
        }
    }

    @Test func aRequestWhileTheLaneIsBusyIsRefused() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 97)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions) {
                $0.signWithKeystoneCoordFlowBinding = true
            }
            let request = Self.request(for: account)

            store.send(.keystoneSigningEvent(.requested(request)))

            await waitForRoot { !completions.value.isEmpty }
            #expect(completions.value.first?.result == .failure(.busy))
            #expect(store.state.pendingKeystoneSigningRequestId == nil)
        }
    }

    @Test func aWithdrawnRequestClosesTheLaneWithoutAnswering() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let account = Self.keystoneAccount(idByte: 98)
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: account, completions: completions)
            let request = Self.request(for: account)
            store.send(.keystoneSigningEvent(.requested(request)))
            await waitForRoot { store.state.signWithKeystoneCoordFlowBinding }

            store.send(.keystoneSigningEvent(.withdrawn(request.id)))

            await waitForRoot { !store.state.signWithKeystoneCoordFlowBinding }
            #expect(store.state.pendingKeystoneSigningRequestId == nil)
            #expect(completions.value.isEmpty)
        }
    }

    @Test func shieldingsRejectStillLeavesForHome() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let completions = LockIsolated<[Completion]>([])
            let store = makeStore(selected: Self.keystoneAccount(idByte: 99), completions: completions)

            store.send(.signWithKeystoneCoordFlow(.sendConfirmation(.rejectTapped)))

            await waitForRoot { store.state.path == nil }
            #expect(completions.value.isEmpty)
        }
    }
}

private func baseNoOpDependencies(_ values: inout DependencyValues) {
    values.audioServices = AudioServicesClient(systemSoundVibrate: { })
    values.databaseFiles = .noOp
    values.derivationTool = .liveValue
    values.diskSpaceChecker = .mockFullDisk
    values.flexaHandler = .noOp
    values.keystoneHandler = .noOp
    values.localAuthentication = .mockAuthenticationSucceeded
    values.mainQueue = .immediate
    values.mnemonic = .mock
    values.readTransactionsStorage.resetZashi = { }
    values.sdkSynchronizer = .noOp
    values.userMetadataProvider.load = { _ in }
    values.walletStorage = .noOp
    values.zcashSDKEnvironment = .testnet
}

@MainActor
private func waitForRoot(
    timeoutNanoseconds: UInt64 = 15_000_000_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(condition(), "Timed out waiting for Root", sourceLocation: sourceLocation)
}
