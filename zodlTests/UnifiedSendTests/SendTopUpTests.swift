import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct SendTopUpTests {
    private nonisolated static let address = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    @Test func leavingSendCancelsTheLookupAndRejectsItsLateResultInANewFlow() async throws {
        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let entered = AsyncStream<Void>.makeStream()
            let cancelled = AsyncStream<Void>.makeStream()
            let account = account(idByte: 91)
            var state = Root.State.initial
            state.$selectedWalletAccount.withLock { $0 = account }
            state.path = .sendCoordFlow
            let store = Store(initialState: state) { Root() } withDependencies: {
                $0.exchangeRate = .noOp
                $0.walletStorage = .noOp
                $0.sdkSynchronizer = .noOp
                $0.sdkSynchronizer.getCustomUnifiedAddress = { _, _ in
                    entered.continuation.yield(())
                    return try await withTaskCancellationHandler {
                        // Represents a pending SDK call; completion is gated by cancellation.
                        try await Task.sleep(for: .seconds(3_600))
                        return nil
                    } onCancel: {
                        cancelled.continuation.yield(())
                    }
                }
            }

            let lookup = store.send(.sendCoordFlow(.topUpSourcePicked(.wallet)))
            var enteredIterator = entered.stream.makeAsyncIterator()
            _ = await enteredIterator.next()
            let requestID = try #require(store.sendCoordFlowState.topUpAddressRequestID)

            store.send(.sendCoordFlow(.sendForm(.dismissRequired)))
            var cancelledIterator = cancelled.stream.makeAsyncIterator()
            _ = await cancelledIterator.next()
            await lookup.finish()
            #expect(store.path == nil)
            #expect(store.sendCoordFlowState.topUpAddressRequestID == nil)

            store.send(.home(.sendTapped))
            // Cancellation cannot retract a response that was already queued at the boundary.
            store.send(.sendCoordFlow(.topUpUnifiedAddressResolved(
                requestID: requestID,
                accountID: account.id,
                address: Self.address
            )))
            #expect(store.path == .sendCoordFlow)
            #expect(store.sendCoordFlowState.path.isEmpty)
        }
    }

    @Test func aCurrentLookupShowsItsResolvedAddress() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let resolved = AsyncStream<Void>.makeStream()
            var state = SendCoordFlow.State()
            state.$selectedWalletAccount.withLock { $0 = account(idByte: 91) }
            let store = Store(initialState: state) {
                SendCoordFlow()
                resolutionObserver(resolved.continuation)
            } withDependencies: {
                $0.sdkSynchronizer = .noOp
                $0.sdkSynchronizer.getCustomUnifiedAddress = { _, _ in
                    try UnifiedAddress(encoding: Self.address, network: .testnet)
                }
            }

            store.send(.topUpSourcePicked(.wallet))
            var resolvedIterator = resolved.stream.makeAsyncIterator()
            _ = await resolvedIterator.next()

            guard case let .addressDetails(details) = store.path.last else {
                Issue.record("Expected the resolved address QR")
                return
            }
            #expect(details.address.data == Self.address)
            #expect(details.maxPrivacy)
            #expect(store.topUpAddressRequestID == nil)
        }
    }

    @Test func aCachedShieldedAddressStillOpensItsQR() async throws {
        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let resolved = AsyncStream<Void>.makeStream()
            var account = account(idByte: 91)
            account.privateUA = try UnifiedAddress(encoding: Self.address, network: .testnet)
            var state = SendCoordFlow.State()
            state.$selectedWalletAccount.withLock { $0 = account }
            let store = Store(initialState: state) {
                SendCoordFlow()
                resolutionObserver(resolved.continuation)
            }

            store.send(.topUpSourcePicked(.wallet))
            var resolvedIterator = resolved.stream.makeAsyncIterator()
            _ = await resolvedIterator.next()

            guard case let .addressDetails(details) = store.path.last else {
                Issue.record("Expected the cached address QR")
                return
            }
            #expect(details.address.data == Self.address)
            #expect(store.topUpAddressRequestID == nil)
        }
    }

    @Test func aResultForThePreviousAccountIsIgnored() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let previousAccount = account(idByte: 91)
            var state = SendCoordFlow.State()
            state.$selectedWalletAccount.withLock { $0 = account(idByte: 92) }
            let requestID = UUID()
            state.topUpAddressRequestID = requestID
            _ = SendCoordFlow().topUpReduce().reduce(into: &state, action: .topUpUnifiedAddressResolved(
                requestID: requestID,
                accountID: previousAccount.id,
                address: Self.address
            ))
            #expect(state.path.isEmpty)
        }
    }

    private func resolutionObserver(_ continuation: AsyncStream<Void>.Continuation) -> Reduce<SendCoordFlow.State, SendCoordFlow.Action> {
        Reduce { _, action in
            if case .topUpUnifiedAddressResolved = action {
                continuation.yield(())
            }
            return .none
        }
    }

    private func account(idByte: UInt8) -> WalletAccount {
        WalletAccount(Account(
            id: AccountUUID(id: [UInt8](repeating: idByte, count: 16)),
            name: "Zapp",
            keySource: nil,
            seedFingerprint: nil,
            hdAccountIndex: Zip32AccountIndex(0),
            ufvk: nil,
            uivk: nil
        ))
    }
}
