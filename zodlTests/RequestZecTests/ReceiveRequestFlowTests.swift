//
//  ReceiveRequestFlowTests.swift
//  zodlTests
//

import ComposableArchitecture
import Testing
@testable import zodl_internal

/// Phase 14 §4.1 moved the Request chain out of Receive's `NavigationStack` and into its own
/// presentation so it rises the way Android's `REQUEST` route does. These cover the behaviour that
/// moved with it — the chain still advances in the same order, still carries the segment's own
/// address, and Cancel now closes the presentation instead of emptying a shared stack.
@Suite struct ReceiveRequestFlowTests {
    private let address = "u1someshieldedaddress".redacted

    @MainActor @Test func theKeyboardAdvancesToTheMemoScreenCarryingTheAmountAndAddress() async {
        let state = ReceiveRequestFlow.State(address: address, maxPrivacy: true)
        let store = TestStore(initialState: state) { ReceiveRequestFlow() }
        store.exhaustivity = .off

        await store.send(.zecKeyboard(.nextTapped))

        #expect(store.state.path.count == 1)

        guard case .requestZec(let pushed) = store.state.path.last else {
            Issue.record("Expected the memo screen to be pushed")
            return
        }

        // The address is the segment the user was looking at on Receive, not a hardcoded
        // shielded one — this is why the chain could not simply reuse `RequestZecCoordFlow`.
        #expect(pushed.address == address)
        #expect(pushed.maxPrivacy)
    }

    @MainActor @Test func requestingFromTheMemoScreenPushesTheSummary() async {
        var state = ReceiveRequestFlow.State(address: address, maxPrivacy: false)
        state.path.append(.requestZec(state.requestZecState))

        let store = TestStore(initialState: state) { ReceiveRequestFlow() }
        store.exhaustivity = .off

        await store.send(.path(.element(id: 0, action: .requestZec(.requestTapped))))

        #expect(store.state.path.count == 2)

        guard case .requestZecSummary = store.state.path.last else {
            Issue.record("Expected the summary to be pushed")
            return
        }
    }

    /// Cancel used to `path.removeAll()` back to Receive. The chain is its own presentation now,
    /// so the equivalent is asking to be dismissed — Receive clears the cover on this.
    @MainActor @Test func cancellingTheSummaryAsksToBeDismissed() async {
        var state = ReceiveRequestFlow.State(address: address, maxPrivacy: true)
        state.path.append(.requestZecSummary(state.requestZecState))

        let store = TestStore(initialState: state) { ReceiveRequestFlow() }
        store.exhaustivity = .off

        await store.send(.path(.element(id: 0, action: .requestZecSummary(.cancelRequestTapped))))
        await store.receive(\.dismissRequested)
    }
}
