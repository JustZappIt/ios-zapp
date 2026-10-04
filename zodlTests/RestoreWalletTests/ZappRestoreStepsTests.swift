//
//  ZappRestoreStepsTests.swift
//  zodlTests
//
//  The Zapp restore flow's seed entry and birthday steps (Android's `ZappRestoreFlowVM`).
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal
@preconcurrency import ZcashLightClientKit

@MainActor struct ZappRestoreBirthdayTests {
    private let sapling = ZcashNetworkBuilder.network(for: .testnet).constants.saplingActivationHeight

    private func makeStore(
        _ state: ZappRestoreBirthday.State = .initial,
        estimate: BlockHeight = 2_000_000
    ) -> TestStore<ZappRestoreBirthday.State, ZappRestoreBirthday.Action> {
        TestStore(initialState: state) {
            ZappRestoreBirthday()
        } withDependencies: {
            $0.zcashSDKEnvironment = .testnet
            $0.sdkSynchronizer = .noOp
            $0.sdkSynchronizer.estimateBirthdayHeight = { _ in estimate }
            $0.date = DateClient(now: { Date(timeIntervalSince1970: 1_790_000_000) })
        }
    }

    @Test func blankHeightScansFromSapling() async {
        let store = makeStore()
        await store.send(.primaryTapped)
        await store.receive(\.restoreRequested, sapling)
    }

    @Test func typedHeightIsUsed() async {
        let store = makeStore()
        await store.send(.heightTextChanged("2 500 000x")) { $0.heightText = "2500000" }
        await store.send(.primaryTapped)
        await store.receive(\.restoreRequested, 2_500_000)
    }

    @Test func heightBelowSaplingIsRefused() async {
        var state = ZappRestoreBirthday.State.initial
        state.heightText = "1"
        let store = makeStore(state)
        await store.send(.primaryTapped) {
            $0.errorMessage = String(localizable: .restoreFlowErrorBirthdayTooLow(String(sapling)))
        }
    }

    /// "Skip: scan everything" means the whole chain, whatever is half-typed in the field.
    @Test func skipIgnoresTheField() async {
        var state = ZappRestoreBirthday.State.initial
        state.heightText = "2500000"
        let store = makeStore(state)
        await store.send(.skipTapped)
        await store.receive(\.restoreRequested, sapling)
    }

    @Test func estimateFillsTheHeightTabInsteadOfRestoring() async {
        var state = ZappRestoreBirthday.State.initial
        state.mode = .date
        let store = makeStore(state, estimate: 2_100_000)
        await store.send(.primaryTapped) {
            $0.heightText = "2100000"
            $0.mode = .height
        }
    }

    @Test func monthsStayBetweenSaplingAndNow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // September 2026
        #expect(ZappRestoreBirthday.months(for: 2018, now: now) == [10, 11, 12])
        #expect(ZappRestoreBirthday.months(for: 2020, now: now) == Array(1...12))
        #expect(ZappRestoreBirthday.months(for: 2026, now: now).last == Calendar.current.component(.month, from: now))
    }
}

@MainActor struct ZappRestoreSeedEntryTests {
    @Test func pastedPhraseSpreadsAcrossTheGrid() async {
        let phrase = (1...24).map { "word\($0)" }
        let store = TestStore(initialState: ZappRestoreSeedEntry.State.initial) {
            ZappRestoreSeedEntry()
        } withDependencies: {
            $0.mnemonic = .noOp
            $0.mnemonic.suggestWords = { [$0] }
        }
        store.exhaustivity = .off

        var words = ZappRestoreSeedEntry.State.initial.words
        words[5] = "1. " + phrase.joined(separator: ", ")
        await store.send(.binding(.set(\.words, words)))

        #expect(store.state.words == phrase)
        #expect(store.state.wordsValidity.allSatisfy { $0 })
        #expect(store.state.isValidSeed)
    }

    @Test func partialPasteFillsFromTheFocusedField() {
        let current = Array(repeating: "", count: ZappRestoreSeedEntry.wordCount)
        let placed = ZappRestoreSeedEntry.placePastedSeedWords(current, at: 22, words: ["a", "b", "c"])
        #expect(placed[22] == "a")
        #expect(placed[23] == "b")
        #expect(placed.filter { !$0.isEmpty }.count == 2)
    }
}
