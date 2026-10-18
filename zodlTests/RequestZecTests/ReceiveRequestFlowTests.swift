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
/// address, and Cancel now closes the presentation instead of emptying a shared stack. The chain
/// is Android's two stages: the amount screen (with an inline note) goes straight to the QR.
@Suite struct ReceiveRequestFlowTests {
    private let address = "u1someshieldedaddress".redacted

    @MainActor @Test func theKeyboardGoesStraightToTheQRWithTheNote() async {
        let state = ReceiveRequestFlow.State(address: address, maxPrivacy: true)
        let store = TestStore(initialState: state) { ReceiveRequestFlow() }
        store.exhaustivity = .off

        await store.send(.noteChanged("Dinner"))
        await store.send(.zecKeyboard(.nextTapped))

        #expect(store.state.path.count == 1)

        guard case .requestZecSummary(let pushed) = store.state.path.last else {
            Issue.record("Expected the QR page to be pushed")
            return
        }

        // The address is the segment the user was looking at on Receive, not a hardcoded
        // shielded one — this is why the chain could not simply reuse `RequestZecCoordFlow`.
        #expect(pushed.address == address)
        #expect(pushed.maxPrivacy)
        #expect(pushed.memoState.text == "Dinner")
    }

    /// A transparent address cannot take a memo, so a transparent request never carries one.
    @MainActor @Test func aTransparentRequestDropsTheNote() async {
        var state = ReceiveRequestFlow.State(address: "tmTransparent".redacted, maxPrivacy: false)
        state.memo = "Dinner"
        let store = TestStore(initialState: state) { ReceiveRequestFlow() }
        store.exhaustivity = .off

        await store.send(.zecKeyboard(.nextTapped))

        guard case .requestZecSummary(let pushed) = store.state.path.last else {
            Issue.record("Expected the QR page to be pushed")
            return
        }
        #expect(pushed.memoState.text.isEmpty)
    }

    @MainActor @Test func theNoteIsCappedAtTheMemoByteLimit() async {
        let store = TestStore(initialState: ReceiveRequestFlow.State(address: address, maxPrivacy: true)) {
            ReceiveRequestFlow()
        }
        store.exhaustivity = .off

        await store.send(.noteChanged(String(repeating: "é", count: 400)))

        #expect(store.state.memo.utf8.count <= ReceiveRequestFlow.noteByteLimit)
        #expect(store.state.memo.count == ReceiveRequestFlow.noteByteLimit / 2)
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
