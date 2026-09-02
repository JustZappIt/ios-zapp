// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// Reducer-level cover for the gift wiring. The ported model suites cover the pure layer, and
/// every defect these tests pin down lived above it — in Root's routing and in the list reducer —
/// where nothing was asserting anything.
///
/// Serialized because `Root.State.initial` resolves process-global `@Shared` keys.
@Suite(.serialized)
struct GiftRootWiringTests {
    /// `Root.body` is recomputed on every action, so `Scope { GiftCardList() }` builds a fresh
    /// reducer — and anything stored on that reducer value is a fresh instance too. The priced
    /// quote used to live there, so it was gone by the time confirm arrived and the button was a
    /// permanent no-op: the documented recovery path for a card that may already hold committed
    /// money. Driven through `Root()` rather than a standalone store on purpose — a standalone
    /// store retains one reducer value, so the regression is invisible from there (and from the
    /// screen's `#Preview`, which is why it shipped).
    @MainActor
    @Test func aPricedRetryQuoteSurvivesToTheConfirmTap() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .giftCardList

            let store = TestStore(initialState: state) {
                Root()
            } withDependencies: {
                $0.giftRetryQuote = GiftRetryQuoteStore()
                // Stops the flow before anything can spend; the assertion is about whether the
                // confirm was accepted at all, not about what it goes on to do.
                $0.localAuthentication.authenticate = { false }
            }
            store.exhaustivity = .off

            await store.send(.giftCardList(.retryPriced(Self.review, Self.quote)))
            await store.send(.giftCardList(.retryConfirmTapped))

            // The discriminating assertion: a confirm that could not find its quote returns
            // `.none` and leaves the review sheet open.
            #expect(store.state.giftCardListState.retryReview == nil)

            await store.finish()
        }
    }

    /// A claim already on screen is not interrupted. Its scan is still running and its effects
    /// still land on `giftClaimState`, so replacing that state showed one card's result under
    /// another card's identity — and because the destination never changed, the view's
    /// `onDisappear` teardown never fired to release the first link.
    @Test func aSecondGiftLinkDoesNotReplaceAClaimAlreadyOnScreen() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .giftClaim
            state.giftClaimState = GiftClaim.State(token: "first-token")

            reduceDestination(&state, .giftLinkReceived("https://gift.justzappit.xyz/c/v1#k=second"))

            #expect(state.giftClaimState.token == "first-token")
            #expect(state.destinationState.destination == .giftClaim)
        }
    }

    /// The claim screen opens without a wallet — that is what its needs-wallet stage is for — so
    /// dismissing it must not land on home, which over an uninitialized wallet is tab chrome with
    /// no route back until the next foreground happens to re-run initialization.
    @MainActor
    @Test func dismissingAClaimWithoutAWalletReturnsToOnboarding() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .giftClaim
            state.appInitializationState = .keysMissing

            // The full reducer, not just `coordinatorReduce()`: the dismiss returns an
            // `.updateDestination` effect that only `destinationReduce()` handles.
            let store = TestStore(initialState: state) {
                Root()
            }
            store.exhaustivity = .off

            await store.send(.giftClaim(.delegate(.dismiss)))
            await store.skipReceivedActions(strict: false)

            #expect(store.state.destinationState.destination == .onboarding)
        }
    }

    /// The counterpart: with a wallet, dismissing still goes home.
    @MainActor
    @Test func dismissingAClaimWithAWalletReturnsHome() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .giftClaim
            state.appInitializationState = .initialized

            let store = TestStore(initialState: state) {
                Root()
            }
            store.exhaustivity = .off

            await store.send(.giftClaim(.delegate(.dismiss)))
            await store.skipReceivedActions(strict: false)

            #expect(store.state.destinationState.destination == .home)
        }
    }

    /// `docs/gift-cards.md` §6.4: the guard belongs on the use path, not on one screen's action.
    /// Three alerts (`walletStateFailed`, `differentSeed`, `existingWallet`) reach `.resetZashi`
    /// directly, and that wipe deletes the only copy of every unshared card's bearer seed.
    @MainActor
    @Test func aDirectResetIsRefusedWhileAnUnsharedCardHoldsFunds() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .home

            let store = TestStore(initialState: state) {
                Root().initializationReduce()
            } withDependencies: {
                $0.giftCardStorage.hasUnsharedFunds = { _ in true }
                $0.receivedGiftStorage.hasUnsettledClaims = { false }
            }
            store.exhaustivity = .off

            await store.send(.initialization(.resetZashi))
            await store.skipReceivedActions(strict: false)

            #expect(store.state.alert != nil)
            #expect(!store.state.hasClearedGiftResetGuard)
        }
    }

    /// An unreadable store blocks too: guessing "empty" wrong destroys money.
    @MainActor
    @Test func aDirectResetIsRefusedWhenTheGiftStoreCannotBeRead() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.destinationState.destination = .home

            let store = TestStore(initialState: state) {
                Root().initializationReduce()
            } withDependencies: {
                $0.giftCardStorage.hasUnsharedFunds = { _ in throw GiftStoreCorrupt(message: "unreadable") }
                $0.receivedGiftStorage.hasUnsettledClaims = { false }
            }
            store.exhaustivity = .off

            await store.send(.initialization(.resetZashi))
            await store.skipReceivedActions(strict: false)

            #expect(store.state.alert != nil)
        }
    }

    /// The override is the only thing that lifts the refusal, and it has to expire with the
    /// attempt: left set, a "delete anyway" that then failed would wave the next reset straight
    /// past the guard.
    @Test func theDeleteAnywayOverrideExpiresWithAFailedAttempt() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.allowGiftDataLoss = true
            state.hasClearedGiftResetGuard = true
            state.maxResetZashiSDKAttempts = 0

            reduceInitialization(&state, .resetZashiSDKFailed)

            #expect(!state.allowGiftDataLoss)
            #expect(!state.hasClearedGiftResetGuard)
        }
    }

    // MARK: - Helpers

    private func reduceDestination(_ state: inout Root.State, _ action: Root.Action) {
        _ = Root().destinationReduce()._reduce(into: &state, action: action)
    }

    private func reduceInitialization(_ state: inout Root.State, _ action: Root.Action) {
        _ = Root().initializationReduce()._reduce(into: &state, action: action)
    }

    private static let review = GiftCardList.RetryReview(
        cardId: "card-1",
        amountText: "1 ZEC",
        claimFeeReserveText: "0.0001 ZEC",
        networkFeeText: "0.0001 ZEC",
        totalText: "1.0002 ZEC",
        message: nil
    )

    private static var quote: GiftFundingQuote {
        GiftFundingQuote(
            card: try! StoredGiftCard(
                id: "card-1",
                network: "main",
                address: "u1testaddress",
                mnemonic: Self.mnemonic,
                amountZatoshi: 100_000_000,
                birthdayHeight: 2_000_000,
                sourceAccountUuid: "account",
                createdAt: "2026-09-01T00:00:00Z",
                updatedAt: "2026-09-01T00:00:00Z",
                status: .draft,
                fundingTxid: nil,
                fundingFailures: [
                    try! GiftFundingFailure(
                        reason: .expired,
                        attemptedAt: "2026-09-01T00:00:00Z",
                        transactionId: "deadbeef",
                        detectedAt: "2026-09-01T00:01:00Z"
                    )
                ]
            ),
            proposal: .testOnlyFakeProposal(totalFee: 10_000),
            claimFeeReserve: Zatoshi(10_000),
            networkFee: Zatoshi(10_000),
            link: "https://gift.justzappit.xyz/c/v1#k=test"
        )
    }

    private static let mnemonic = [String](repeating: "abandon", count: 23).joined(separator: " ") + " art"
}
