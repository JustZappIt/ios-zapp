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
        var page = 1
        var hasMore = false
        var isLoadingMore = false

        var isEmpty: Bool { !isLoading && !didFail && results.isEmpty }

        var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    enum Action: Equatable {
        case onAppear
        case queryChanged(String)
        case clearQueryTapped
        case reload
        case resultsLoaded(KlipyGIFPage)
        case loadFailed
        case reachedEnd
        case moreLoaded(KlipyGIFPage)
        case moreFailed
        case gifTapped(KlipyGIF)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case selected(KlipyGIF)
        }
    }

    enum CancelID {
        case search
        case more
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
                state.page = 1
                state.hasMore = false
                state.isLoadingMore = false

                let query = state.trimmedQuery

                return .merge(
                    .cancel(id: CancelID.more),
                    .run { send in
                        await send(.resultsLoaded(try await results(query, page: 1)))
                    } catch: { error, send in
                        LoggerProxy.error("Chat GIF search failed: \(error)")
                        await send(.loadFailed)
                    }
                    .cancellable(id: CancelID.search, cancelInFlight: true)
                )

            case .resultsLoaded(let loaded):
                state.isLoading = false
                state.didFail = false
                state.results = loaded.gifs
                state.hasMore = loaded.hasMore

                return .none

            case .loadFailed:
                state.isLoading = false
                state.didFail = true
                state.hasMore = false
                state.results = []

                return .none

            case .reachedEnd:
                guard state.hasMore, !state.isLoading, !state.isLoadingMore else { return .none }

                state.isLoadingMore = true

                let next = state.page + 1
                let query = state.trimmedQuery

                return .run { send in
                    await send(.moreLoaded(try await results(query, page: next)))
                } catch: { error, send in
                    LoggerProxy.error("Chat GIF page \(next) failed: \(error)")
                    await send(.moreFailed)
                }
                .cancellable(id: CancelID.more, cancelInFlight: true)

            case .moreLoaded(let loaded):
                let known = Set(state.results.map(\.id))

                state.isLoadingMore = false
                state.page += 1
                state.hasMore = loaded.hasMore
                state.results.append(contentsOf: loaded.gifs.filter { !known.contains($0.id) })

                return .none

            // The grid keeps what it has: a failed page must not put the footer back on screen to
            // be retried by the same scroll position that just failed.
            case .moreFailed:
                state.isLoadingMore = false
                state.hasMore = false

                return .none

            case .gifTapped(let gif):
                return .send(.delegate(.selected(gif)))

            case .delegate:
                return .none
            }
        }
    }

    private func results(_ query: String, page: Int) async throws -> KlipyGIFPage {
        query.isEmpty
            ? try await klipyGIF.trending(page)
            : try await klipyGIF.search(query, page)
    }
}
