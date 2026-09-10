// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
import ZappOfframp
@testable import zodl_internal

/// The run one row starts, and the three things about it that are invisible on screen: which step
/// a failure lands on, that a failure keeps its own sentence, and that a second session is never
/// minted over a live one.
struct IncreaseReputationStoreTests {
    // MARK: - The list

    @MainActor @Test func theListLeadsWithTheAccountWorthTheMost() async {
        let store = await listStore()

        await store.send(.onAppear)
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }
        }

        #expect(store.state.platforms.first?.id == "LinkedIn")
    }

    /// p2p.me's own client hides Binance in India, so an INR user who tried it would meet a failure
    /// we could have predicted.
    @MainActor @Test func binanceIsHiddenOnTheIndianCorridorOnly() async {
        let inr = await listStore(currencyCode: "INR")
        await inr.send(.onAppear)
        await inr.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }
        }
        #expect(!inr.state.platforms.contains { $0.id == "Binance" })

        let brl = await listStore(currencyCode: "BRL")
        await brl.send(.onAppear)
        await brl.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.platforms = ReputationFixtures.platforms
        }
        #expect(brl.state.platforms.contains { $0.id == "Binance" })
    }

    @MainActor @Test func tappingAVerifiedRowStartsNothing() async {
        var state = IncreaseReputation.State.initial(currencyCode: "INR")
        state.isLoading = false
        state.platforms = [ReputationFixtures.platform(id: "LinkedIn", award: "100", gain: nil, isVerified: true)]

        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.verify = { _, _ in Issue.record("a verified row minted a session"); throw Failure.wrong }
        }

        await store.send(.platformTapped("LinkedIn"))
        #expect(store.state.run == nil)
    }

    // MARK: - The run

    @MainActor @Test func aRunWalksPreparingToDoneAndReportsTheChainsOwnNewLimit() async {
        let store = await runStore(statuses: [
            .preparing,
            .ready(requestURL: "https://share.reclaimprotocol.org/link/abc"),
            .verifying,
            .submitting,
            .done(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000"))
        ])

        await store.send(.platformTapped("LinkedIn")) {
            $0.run = run(stage: .preparing)
        }
        await store.receive(\.statusReceived)
        await store.receive(\.statusReceived) {
            $0.run?.stage = .ready
            $0.run?.launchURL = "https://share.reclaimprotocol.org/link/abc"
        }
        await store.receive(\.statusReceived) {
            $0.run?.stage = .verifying
            $0.lastActiveStage = .verifying
        }
        await store.receive(\.statusReceived) {
            $0.run?.stage = .submitting
            $0.lastActiveStage = .submitting
        }
        await store.receive(\.statusReceived) {
            $0.run?.stage = .done
            $0.run?.newPoints = "100"
            $0.run?.newBuyLimitMicros = "200000000"
        }
        await store.receive(\.runEnded)

        #expect(store.state.steps.allSatisfy { $0.status == .completed })
    }

    /// A failure marks the step it failed *on*, not the first one: "Open Reclaim" showing failed
    /// after the user has clearly opened it is a screen that has lost the plot.
    @MainActor @Test(arguments: [
        (ReclaimStatusModel.verifying, 1),
        (.submitting, 2)
    ])
    func aFailureMarksTheStepItFailedOn(reached: ReclaimStatusModel, index: Int) async {
        let store = await runStore(statuses: [
            .ready(requestURL: "https://example.test/link"),
            reached,
            .failed(.proofGenerationFailed)
        ])
        store.exhaustivity = .off

        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        await store.receive(\.statusReceived)
        await store.receive(\.statusReceived)
        await store.receive(\.runEnded)

        let steps = store.state.steps
        #expect(steps[index].status == .failed)
        #expect(steps.prefix(index).allSatisfy { $0.status == .completed })
        #expect(steps.dropFirst(index + 1).allSatisfy { $0.status == .pending })
    }

    /// Three different reverts mean "one account, one wallet"; the driver already collapses them,
    /// and the sentence they earn is not the generic one.
    @MainActor @Test func alreadyVerifiedElsewhereGetsItsOwnSentence() async {
        let store = await runStore(statuses: [.failed(.alreadyVerifiedElsewhere)])
        store.exhaustivity = .off

        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        await store.receive(\.runEnded)

        #expect(store.state.run?.errorMessage == String(localizable: .increaseReputationErrorAlreadyUsed))
        #expect(store.state.run?.errorMessage != String(localizable: .increaseReputationErrorNetwork))
    }

    /// ☠ The driver's failures cross as `ReclaimFailure.name` and are matched by raw value. A
    /// rename on either side is not a compile error on either side: every case would fall to
    /// `.unknown`, and all nine sentences — `alreadyVerifiedElsewhere`, which is permanent,
    /// included — would collapse into "couldn't reach the network, try again in a moment".
    @Test func everyDriverFailureIsNamedOnThisSideToo() {
        for failure in ReclaimFailure.allCases {
            #expect(ReclaimFailureModel(rawValue: failure.name) != nil, "unmapped: \(failure.name)")
        }
    }

    @Test func everyFailureKeepsASentenceOfItsOwn() {
        let messages = [
            ReclaimFailureModel.notConfigured, .criteriaNotMet, .proofGenerationFailed, .sessionExpired,
            .alreadyVerifiedElsewhere, .addressMismatch, .verificationRejected, .sponsorshipUnavailable, .busy
        ].map(ReputationCopy.failureMessage)

        #expect(Set(messages).count == messages.count)
        #expect(!messages.contains(String(localizable: .increaseReputationErrorNetwork)))
    }

    @MainActor @Test func aSecondRowTappedWhileARunIsLiveIsIgnored() async {
        let started = LockIsolated<[String]>([])
        var state = IncreaseReputation.State.initial(currencyCode: "INR")
        state.isLoading = false
        state.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }

        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.verify = { platformID, _ in
                started.withValue { $0.append(platformID) }
                return ReclaimStatusStream { $0.yield(.preparing) }
            }
        }
        store.exhaustivity = .off

        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        await store.send(.platformTapped("GitHub"))
        await store.send(.cancelRunTapped)
        await store.finish()

        #expect(started.value == ["LinkedIn"])
    }

    /// Cancelling leaves the Reclaim session to expire on its own, and never surfaces later as an
    /// error — the user chose to stop.
    @MainActor @Test func cancellingClearsTheRunWithoutReportingAFailure() async {
        let store = await runStore(statuses: [.ready(requestURL: "https://example.test/link")])
        store.exhaustivity = .off

        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        await store.send(.cancelRunTapped)
        await store.finish()

        #expect(store.state.run == nil)
    }

    // MARK: - Leaving for the Verifier

    @MainActor @Test func theSessionIsHeldOpenUntilTheVerifierActuallyOpened() async {
        let marked = LockIsolated(0)
        let store = await runStore(statuses: [.ready(requestURL: "https://example.test/link")]) {
            $0.reputation.markVerifierOpened = { marked.withValue { $0 += 1 } }
        }
        store.exhaustivity = .off

        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)

        await store.send(.verifierOpened(platformID: "LinkedIn", accepted: false))
        await store.finish()
        #expect(marked.value == 0)

        await store.send(.verifierOpened(platformID: "LinkedIn", accepted: true))
        await store.finish()
        #expect(marked.value == 1)
    }

    /// A launch callback can outlive the run that started it. Marking the run after it as opened
    /// would stop that one re-minting before the user has left, and its link then ages out while
    /// nobody watches the session it names.
    @MainActor @Test func aCallbackFromAnAbandonedRunNeverMarksTheRunAfterIt() async {
        let marked = LockIsolated(0)
        let store = await runStore(statuses: [.ready(requestURL: "https://example.test/link")]) {
            $0.reputation.markVerifierOpened = { marked.withValue { $0 += 1 } }
        }
        store.exhaustivity = .off

        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        await store.send(.cancelRunTapped)
        await store.send(.platformTapped("GitHub"))
        await store.receive(\.statusReceived)

        await store.send(.verifierOpened(platformID: "LinkedIn", accepted: true))
        await store.finish()

        #expect(marked.value == 0)
    }

    // MARK: - The return link

    /// A resume counts opening the Verifier as done: the user has already been and come back, so a
    /// failure here must not mark the step they clearly completed.
    @MainActor @Test func aResumedRunNeverMarksOpeningTheVerifierAsFailed() async {
        var state = IncreaseReputation.State.initial(
            currencyCode: "INR",
            resumeSessionID: "session-1",
            resumePlatformID: "LinkedIn"
        )
        state.isLoading = false
        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.reputation.resume = { _, _, _ in
                ReclaimStatusStream { continuation in
                    continuation.yield(.failed(.sessionExpired))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.statusReceived)
        await store.receive(\.runEnded)
        await store.finish()

        let steps = store.state.steps
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .failed)
    }

    /// A cold start has lost the poller, so the callback's session id is what rebuilds it. It picks
    /// up at `verifying` — the user has already been and come back.
    @MainActor @Test func aColdStartResumesTheSessionTheReturnLinkNamed() async {
        let resumed = LockIsolated<String?>(nil)
        let state = IncreaseReputation.State.initial(
            currencyCode: "INR",
            resumeSessionID: "session-1",
            resumePlatformID: "LinkedIn"
        )
        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.reputation.resume = { _, _, sessionID in
                resumed.setValue(sessionID)
                return ReclaimStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.finish()

        #expect(resumed.value == "session-1")
        // Consumed exactly once, so a re-appearance cannot enqueue the same session again.
        #expect(store.state.resumeSessionID == nil)
        #expect(store.state.resumePlatformID == nil)
    }

    // MARK: - Helpers

    private enum Failure: Error { case wrong }

    private func run(stage: IncreaseReputation.State.Stage) -> IncreaseReputation.State.Run {
        IncreaseReputation.State.Run(platformID: "LinkedIn", name: "LinkedIn", stage: stage)
    }

    @MainActor private func listStore(currencyCode: String = "INR") async -> TestStoreOf<IncreaseReputation> {
        await TestStore(initialState: .initial(currencyCode: currencyCode)) { IncreaseReputation() }
        withDependencies: {
            $0.reputation.summary = { _ in
                ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0")
            }
        }
    }

    @MainActor private func runStore(
        statuses: [ReclaimStatusModel],
        currencyCode: String = "INR",
        extra: @escaping (inout DependencyValues) -> Void = { _ in }
    ) async -> TestStoreOf<IncreaseReputation> {
        var state = IncreaseReputation.State.initial(currencyCode: currencyCode)
        state.isLoading = false
        state.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }
        return await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.verify = { _, _ in
                ReclaimStatusStream { continuation in
                    statuses.forEach { continuation.yield($0) }
                    continuation.finish()
                }
            }
            extra(&$0)
        }
    }
}
