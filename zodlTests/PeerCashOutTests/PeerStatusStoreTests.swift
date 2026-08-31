// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@MainActor
struct PeerStatusStoreTests {
    /// KMP reports a failed order read as a progress value whose `order` is nil. Dropping that
    /// value leaves a first load pending forever and hides the only useful failure from the user.
    @Test func orderlessFailureProgressStopsInitialLoadingAndIsVisible() async {
        let progressStream = AsyncStream<PeerProgress>.makeStream()
        let runnerStream = AsyncStream<PeerRunnerState>.makeStream()
        let observationStarted = AsyncStream<Void>.makeStream()
        var startedIterator = observationStarted.stream.makeAsyncIterator()
        let readStartedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let failure = failureProgress()
        let store = TestStore(initialState: PeerOrderDetail.State(depositID: Self.depositID)) {
            PeerOrderDetail()
        } withDependencies: {
            $0.date.now = { readStartedAt }
            $0.peerCashOut.observeOrder = { requestedID in
                #expect(requestedID == Self.depositID)
                observationStarted.continuation.yield()
                observationStarted.continuation.finish()
                return progressStream.stream
            }
            $0.peerCashOut.runnerState = { runnerStream.stream }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.readGeneration = 1
            $0.runnerGeneration = 1
        }
        _ = await startedIterator.next()

        progressStream.continuation.yield(failure)
        await store.receive(.orderProgressReceived(
            failure,
            readStartedAt: readStartedAt,
            generation: 1
        )) {
            $0.latestProgress = failure
            $0.isLoading = false
            $0.readErrorMessage = failure.failure?.message
        }

        await store.send(.onDisappear) {
            $0.readGeneration = 2
            $0.runnerGeneration = 2
        }
    }

    /// Recovery can fail before the runner stream exists. That is an explicit failed UI state,
    /// rather than an effect error that leaves the setup screen pending indefinitely.
    @Test func progressStartupFailureStopsLoadingAndReachesTheUIState() async {
        let message = String(localizable: .peerFailureGeneric)
        let store = TestStore(initialState: PeerCashOutProgress.State(attemptID: Self.attemptID)) {
            PeerCashOutProgress()
        } withDependencies: {
            $0.peerCashOut.recoverCashOut = { _ in throw TestError.startup }
        }

        await store.send(.onAppear) {
            $0.observationGeneration = 1
        }
        await store.receive(.startupFailed(message, generation: 1)) {
            $0.startupErrorMessage = message
            $0.isLoading = false
        }

        #expect(store.state.title == String(localizable: .peerProgressTitleFailed))
    }

    /// A poll from before settlement may answer afterward. The settlement starts a new generation,
    /// the old response is rejected, and only a read begun after `settledAt` releases the controls.
    @Test func settledOrderActionRejectsTheOldPollAndRestartsFromItsCausalBoundary() async {
        let freshStream = AsyncStream<PeerProgress>.makeStream()
        let observationStarted = AsyncStream<Void>.makeStream()
        var startedIterator = observationStarted.stream.makeAsyncIterator()
        let settledAt = Date(timeIntervalSince1970: 1_700_000_200)
        let freshReadStartedAt = settledAt.addingTimeInterval(1)
        let oldOrder = order(remaining: "20000000", offersWithdrawal: true)
        let freshOrder = order(remaining: "0", offersWithdrawal: false)
        var state = PeerOrderDetail.State(depositID: Self.depositID)
        state.order = oldOrder
        state.readAt = settledAt.addingTimeInterval(-100)
        state.readGeneration = 7
        state.runnerGeneration = 3
        state.action = PeerOrderAction(
            depositID: Self.depositID,
            kind: .withdraw,
            latest: nil,
            isRunning: true,
            settledAt: nil
        )

        let store = TestStore(initialState: state) { PeerOrderDetail() } withDependencies: {
            $0.date.now = { freshReadStartedAt }
            $0.peerCashOut.observeOrder = { _ in
                observationStarted.continuation.yield()
                observationStarted.continuation.finish()
                return freshStream.stream
            }
        }
        var runnerState = PeerRunnerState.empty
        runnerState.orderActions[Self.depositID] = PeerOrderAction(
            depositID: Self.depositID,
            kind: .withdraw,
            latest: nil,
            isRunning: false,
            settledAt: settledAt
        )

        await store.send(.runnerStateChanged(runnerState, generation: 3)) {
            $0.action = runnerState.orderActions[Self.depositID]
            $0.readGeneration = 8
        }
        #expect(store.state.isBusy)
        _ = await startedIterator.next()

        let stale = orderProgress(order: oldOrder)
        await store.send(.orderProgressReceived(
            stale,
            // This deliberately looks newer than settlement, reproducing the old response-time
            // stamp. Its prior generation still makes it ineligible to update visible state.
            readStartedAt: settledAt.addingTimeInterval(100),
            generation: 7
        ))
        #expect(store.state.readAt == settledAt.addingTimeInterval(-100))
        #expect(store.state.isBusy)

        let fresh = orderProgress(order: freshOrder)
        freshStream.continuation.yield(fresh)
        await store.receive(.orderProgressReceived(
            fresh,
            readStartedAt: freshReadStartedAt,
            generation: 8
        )) {
            $0.latestProgress = fresh
            $0.order = freshOrder
            $0.readAt = freshReadStartedAt
        }
        #expect(!store.state.isBusy)
        #expect(!store.state.offersWithdrawal)

        await store.send(.onDisappear) {
            $0.readGeneration = 9
            $0.runnerGeneration = 4
        }
    }

    private static let attemptID = "0123456789abcdef0123456789abcdef"
    private static let depositID = "0x777777779d229cdf3110e9de47943791c26300ef_1"

    private func failureProgress() -> PeerProgress {
        PeerProgress(
            subjectID: Self.depositID,
            kind: .failed,
            step: .settling,
            amount: nil,
            txHash: nil,
            depositID: Self.depositID,
            order: nil,
            failure: PeerFailure(
                code: "INDEXER_UNAVAILABLE",
                step: .settling,
                retryable: true,
                allowsManualRetry: true,
                nothingEscrowed: false,
                recovery: nil,
                escrowRevertBucket: nil
            ),
            isTerminal: true
        )
    }

    private func orderProgress(order: PeerOrder) -> PeerProgress {
        PeerProgress(
            subjectID: Self.depositID,
            kind: .orderLive,
            step: .awaitingBuyer,
            amount: nil,
            txHash: nil,
            depositID: Self.depositID,
            order: order,
            failure: nil,
            isTerminal: false
        )
    }

    private func order(remaining: String, offersWithdrawal: Bool) -> PeerOrder {
        PeerOrder(
            depositID: Self.depositID,
            phase: remaining == "0" ? .closed : .waiting,
            isFinished: remaining == "0",
            acceptingIntents: true,
            gross: UsdcAmount(micros: "20000000") ?? .zero,
            remaining: UsdcAmount(micros: remaining) ?? .zero,
            sold: .zero,
            locked: .zero,
            withdrawn: .zero,
            withdrawable: UsdcAmount(micros: remaining) ?? .zero,
            destinationCode: "revolut",
            currencyCodes: ["EUR"],
            buyerLegs: [],
            offersWithdrawal: offersWithdrawal,
            offersMatchingToggle: false,
            isHiddenFromBuyers: false,
            openedAt: nil,
            lastActivityAt: nil,
            explorerURL: nil
        )
    }
}

private enum TestError: Error {
    case startup
}
