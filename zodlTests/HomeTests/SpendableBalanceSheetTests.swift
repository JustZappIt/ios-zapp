//
//  SpendableBalanceSheetTests.swift
//  zodlTests
//
//  The Pay tab's balance breakdown opens the Spendable balance sheet, mirroring Android's
//  `BalanceWidgetVM.onBalanceButtonClick` → `SpendableBalanceArgs`.
//

import Testing
import ComposableArchitecture
@testable import zodl_internal
@testable @preconcurrency import ZcashLightClientKit

@MainActor
@Suite(.serialized) struct SpendableBalanceSheetTests {
    @Test func tappingTheBreakdownPresentsTheSpendableSheet() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            let store = TestStore(initialState: .initial) { Home() }

            await store.send(.zappSpendableBalanceTapped) {
                $0.isZappSpendableBalanceSheetPresented = true
            }
        }
    }

    @Test func dismissClosesTheSheet() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = Home.State.initial
            initial.isZappSpendableBalanceSheetPresented = true
            let store = TestStore(initialState: initial) { Home() }

            await store.send(.zappSpendableBalances(.dismissTapped)) {
                $0.isZappSpendableBalanceSheetPresented = false
            }
        }
    }

    @Test func shieldingFromTheSheetShieldsAndClosesIt() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            let shieldCalls = LockIsolated(0)
            var initial = Home.State.initial
            initial.isZappSpendableBalanceSheetPresented = true
            let store = TestStore(initialState: initial) {
                Home()
            } withDependencies: {
                $0.shieldingProcessor.shieldFunds = { shieldCalls.withValue { $0 += 1 } }
            }

            await store.send(.zappSpendableBalances(.shieldFundsTapped)) {
                $0.isZappSpendableBalanceSheetPresented = false
            }
            #expect(shieldCalls.value == 1)
        }
    }
}
