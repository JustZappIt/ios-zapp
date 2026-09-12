// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// Where the user stands with the exchange, read fresh on every visit.
///
/// Nothing here is cached: a completed buy credits reputation, so a value stored from the last
/// visit is stale in exactly the moment the user is most likely to look. Nothing here is computed
/// either — the limits come from the Diamond, which is the only place the effective number exists.
@Reducer
struct Reputation {
    @ObservableState
    struct State: Equatable {
        enum Content: Equatable {
            case loading
            case ready(ReputationSummaryModel)
            /// Terminal: verifying will not help, so the screen says so and offers nothing.
            case blocked
            /// Base was unreachable. Never rendered as 0 RP — that shows a verified user a wall.
            case unreadable
        }

        enum PrimaryAction: Equatable {
            case buy
            case verifyToBuy
            case retry
        }

        var currencyCode: String
        var content: Content = .loading
        var isInfoPresented = false
        var isLoading = false
        /// Buy entry checks durable purchase recovery before applying the new-purchase gate.
        var isBuyEntry = false

        var summary: ReputationSummaryModel? {
            guard case let .ready(summary) = content else { return nil }
            return summary
        }

        /// The bottom bar's one CTA — whatever the user wants next, which is buying as soon as
        /// they can. Nil only when nothing is actionable, where an enabled-looking button would be
        /// a lie and a disabled one furniture.
        var primaryAction: PrimaryAction? {
            switch content {
            case .loading, .blocked: return nil
            case .unreadable: return .retry
            case let .ready(summary): return summary.canStartBuy ? .buy : .verifyToBuy
            }
        }

        /// Raising the limit is always reachable but never the main button once buying works.
        /// Absent at 0 RP, where it would duplicate the primary, and at the ceiling, where it buys
        /// nothing. A failed read still offers it — the failure is ours, not theirs.
        var isRaiseLimitVisible: Bool {
            switch content {
            case .loading, .blocked: return false
            case .unreadable: return true
            case let .ready(summary): return summary.canStartBuy && !summary.isAtCeiling
            }
        }

        /// The Diamond's own number, or the single word that stands in for it while buying is
        /// locked — never a rendered "$0", which reads as a bug rather than as a gate.
        var buyLimitText: String? {
            guard let summary else { return nil }
            return summary.canStartBuy
                ? String(localizable: .reputationAmountUsd(ReputationCopy.usd(summary.buyLimitMicros)))
                : String(localizable: .reputationLimitLocked)
        }

        var buyLimitCaption: String? {
            guard let summary else { return nil }
            if !summary.canStartBuy { return String(localizable: .reputationLimitLockedCaption) }
            return summary.isAtCeiling
                ? String(localizable: .reputationLimitCaptionAtCeiling)
                : String(localizable: .reputationLimitCaption)
        }

        static func initial(currencyCode: String, isBuyEntry: Bool = false) -> State {
            State(currencyCode: currencyCode, isBuyEntry: isBuyEntry)
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case summaryLoaded(ReputationSummaryModel)
        case loadFailed
        case retryTapped
        case buyTapped
        case raiseLimitTapped
        case infoTapped
        case infoDismissed
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
            case checkBuy
            case buy(currencyCode: String)
            case raiseLimit(currencyCode: String)
        }
    }

    @Dependency(\.reputation) var reputation

    private enum CancelID { case load }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // Re-read on every appearance rather than on construction alone. A completed buy
            // credits reputation and a verification raises the limit, so the value this screen
            // most often returns to is the one most likely to have moved since it was read.
            case .onAppear, .retryTapped:
                guard !state.isLoading else { return .none }
                state.isLoading = true
                if state.summary == nil { state.content = .loading }
                if state.isBuyEntry { return .send(.delegate(.checkBuy)) }
                let currencyCode = state.currencyCode
                return .run { send in
                    await send(.summaryLoaded(try await reputation.summary(currencyCode: currencyCode)))
                } catch: { _, send in
                    await send(.loadFailed)
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .summaryLoaded(summary):
                state.isLoading = false
                state.content = summary.isBlocked ? .blocked : .ready(summary)
                return .none

            case .loadFailed:
                state.isLoading = false
                // A failed *refresh* leaves the last good read on screen: it was true a moment
                // ago, and blanking it over a dropped request is the worse lie.
                if state.summary == nil { state.content = .unreadable }
                return .none

            case .buyTapped:
                guard state.summary?.canStartBuy == true else { return .none }
                state.isLoading = false
                return .merge(.cancel(id: CancelID.load), .send(.delegate(.buy(currencyCode: state.currencyCode))))

            case .raiseLimitTapped:
                guard state.content != .blocked else { return .none }
                state.isLoading = false
                return .merge(.cancel(id: CancelID.load), .send(.delegate(.raiseLimit(currencyCode: state.currencyCode))))

            case .infoTapped:
                state.isInfoPresented = true
                return .none

            case .infoDismissed:
                state.isInfoPresented = false
                return .none

            case .backTapped:
                state.isLoading = false
                return .merge(.cancel(id: CancelID.load), .send(.delegate(.close)))

            case .onDisappear:
                // SwiftUI cancels .task, and TCA deliberately does not send loadFailed for
                // cancellation. Clear the latch as well so the next visit can read again.
                state.isLoading = false
                return .cancel(id: CancelID.load)

            case .delegate:
                return .none
            }
        }
    }
}
