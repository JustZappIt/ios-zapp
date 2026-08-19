import ComposableArchitecture
import Testing
@testable import zodl_internal

@Suite
struct PortfolioChartSettingsVMTests {
    @Test
    func saveButtonIsDisabledUntilSelectionChanges() {
        var state = PortfolioChartSetup.State(isEnabled: true, savedIsEnabled: true)
        #expect(state.isSaveButtonDisabled)
        state.isEnabled = false
        #expect(!state.isSaveButtonDisabled)
    }

    @MainActor
    @Test
    func onAppearLoadsStoredSelection() async {
        let store = TestStore(initialState: PortfolioChartSetup.State()) {
            PortfolioChartSetup()
        } withDependencies: {
            $0.userStoredPreferences.portfolioChartEnabled = { false }
        }

        await store.send(.onAppear) {
            $0.isEnabled = false
            $0.savedIsEnabled = false
        }
    }

    @MainActor
    @Test
    func savePersistsAndReturnsHome() async {
        let saved = LockIsolated<Bool?>(nil)
        let store = TestStore(initialState: PortfolioChartSetup.State(isEnabled: false, savedIsEnabled: true)) {
            PortfolioChartSetup()
        } withDependencies: {
            $0.userStoredPreferences.setPortfolioChartEnabled = { saved.setValue($0) }
        }

        await store.send(.saveChangesTapped) {
            $0.savedIsEnabled = false
        }
        await store.receive(\.backToHomeTapped)
        #expect(saved.value == false)
    }
}
