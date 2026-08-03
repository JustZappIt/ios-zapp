//
//  ChatGIFPickerStore.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatGIFPicker {
    @ObservableState
    struct State: Equatable {
        var query = ""
        var results: [KlipyGIF] = []
        var isLoading = true
        var didFail = false

        var isEmpty: Bool { !isLoading && !didFail && results.isEmpty }
    }

    enum Action: Equatable {
        case onAppear
        case queryChanged(String)
        case clearQueryTapped
        case reload
        case resultsLoaded([KlipyGIF])
        case loadFailed
        case gifTapped(KlipyGIF)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case selected(KlipyGIF)
        }
    }

    enum CancelID {
        case search
    }

    private let searchDebounce = Duration.milliseconds(350)

    @Dependency(\.continuousClock) var clock
    @Dependency(\.klipyGIF) var klipyGIF

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.reload)

            case .queryChanged(let query):
                state.query = query

                return .run { [debounce = searchDebounce] send in
                    try await clock.sleep(for: debounce)
                    await send(.reload)
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .clearQueryTapped:
                state.query = ""

                return .send(.reload)

            case .reload:
                state.isLoading = true
                state.didFail = false

                let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)

                return .run { send in
                    let results = query.isEmpty
                        ? try await klipyGIF.trending()
                        : try await klipyGIF.search(query)

                    await send(.resultsLoaded(results))
                } catch: { error, send in
                    LoggerProxy.error("Chat GIF search failed: \(error)")
                    await send(.loadFailed)
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .resultsLoaded(let results):
                state.isLoading = false
                state.didFail = false
                state.results = results

                return .none

            case .loadFailed:
                state.isLoading = false
                state.didFail = true
                state.results = []

                return .none

            case .gifTapped(let gif):
                return .send(.delegate(.selected(gif)))

            case .delegate:
                return .none
            }
        }
    }
}
