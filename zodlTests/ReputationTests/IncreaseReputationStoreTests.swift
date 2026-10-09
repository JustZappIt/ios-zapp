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
            $0.uuid = .incrementing
            $0.reputation.verify = { _, _, _ in Issue.record("a verified row minted a session"); throw Failure.wrong }
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
            $0.summaryRevision = 1
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
            $0.uuid = .incrementing
            $0.reputation.verify = { platformID, _, _ in
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

    @MainActor @Test func theSessionIsHeldOpenUntilTheVerifierActuallyOpened() async throws {
        let marked = LockIsolated<[UUID]>([])
        let store = await liveRunStore(marked: marked)
        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        let id = try #require(store.state.run?.id)

        let refused = await store.send(.verifierOpened(runID: id, accepted: false))
        await refused.finish()
        #expect(marked.value.isEmpty)
        let accepted = await store.send(.verifierOpened(runID: id, accepted: true))
        await accepted.finish()
        #expect(marked.value == [id])
        await store.send(.cancelRunTapped)
        await store.finish()
    }

    /// Retrying the same platform must be distinct from the run whose open callback is delayed.
    @MainActor @Test(arguments: ["LinkedIn", "GitHub"])
    func abandonedCallbacksAndStatusesCannotAffectTheNextRun(nextPlatform: String) async throws {
        let marked = LockIsolated<[UUID]>([])
        let store = await liveRunStore(marked: marked)
        await store.send(.platformTapped("LinkedIn"))
        await store.receive(\.statusReceived)
        let oldID = try #require(store.state.run?.id)
        await store.send(.cancelRunTapped)
        await store.send(.platformTapped(nextPlatform))
        await store.receive(\.statusReceived)
        let newID = try #require(store.state.run?.id)
        #expect(newID != oldID)

        let stale = await store.send(.verifierOpened(runID: oldID, accepted: true))
        await stale.finish()
        await store.send(.statusReceived(runID: oldID, status: .failed(.network)))
        await store.send(.runEnded(runID: oldID))
        #expect(marked.value.isEmpty)
        #expect(store.state.run?.id == newID)
        #expect(store.state.run?.stage == .ready)
        let current = await store.send(.verifierOpened(runID: newID, accepted: true))
        await current.finish()
        #expect(marked.value == [newID])
        await store.send(.cancelRunTapped)
        await store.finish()
    }

    @MainActor private func liveRunStore(marked: LockIsolated<[UUID]>) async -> TestStoreOf<IncreaseReputation> {
        let store = await runStore(statuses: []) {
            $0.reputation.verify = { _, _, _ in
                ReclaimStatusStream { $0.yield(.ready(requestURL: "https://example.test/link")) }
            }
            $0.reputation.markVerifierOpened = { id in marked.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off
        return store
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
            $0.uuid = .incrementing
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.reputation.resume = { _, _, _, _ in
                ReclaimStatusStream { continuation in
                    continuation.yield(.failed(.sessionExpired))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.send(.resumeConfirmed)
        await store.receive(\.statusReceived)
        await store.receive(\.runEnded)
        await store.finish()

        let steps = store.state.steps
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .failed)
    }

    /// A cold start has lost the poller, so the callback's session id is what rebuilds it. It picks
    /// up at `verifying` — the user has already been and come back.
    @MainActor @Test func aColdStartRequiresConfirmationBeforeResumingTheSession() async {
        let resumed = LockIsolated<String?>(nil)
        let state = IncreaseReputation.State.initial(
            currencyCode: "INR",
            resumeSessionID: "session-1",
            resumePlatformID: "LinkedIn"
        )
        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.uuid = .incrementing
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.reputation.resume = { _, _, sessionID, _ in
                resumed.setValue(sessionID)
                return ReclaimStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.finish()

        #expect(resumed.value == nil)
        #expect(store.state.requiresResumeConfirmation)
        await store.send(.resumeConfirmed)
        await store.finish()
        #expect(resumed.value == "session-1")
        // Consumed exactly once, so a re-appearance cannot enqueue the same session again.
        #expect(store.state.resumeSessionID == nil)
        #expect(store.state.resumePlatformID == nil)
    }

    @MainActor @Test func rejectingAColdReturnNeverResumesIt() async {
        let state = IncreaseReputation.State.initial(currencyCode: "INR", resumeSessionID: "foreign-session", resumePlatformID: "LinkedIn")
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.reputation.resume = { _, _, _, _ in
                Issue.record("A return URL must not authorize a verification")
                return ReclaimStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.finish()
        #expect(store.state.requiresResumeConfirmation)
        await store.send(.backTapped)
        await store.receive(\.delegate.close)
        await store.send(.resumeConfirmed)
        await store.finish()
        #expect(!store.state.requiresResumeConfirmation)
        #expect(store.state.run == nil)
    }

    @MainActor @Test func aCompletedVerificationSupersedesOlderSummaryResponses() async {
        var state = IncreaseReputation.State.initial(currencyCode: "INR")
        state.run = run(stage: .submitting)
        let verified = ReputationFixtures.platform(id: "LinkedIn", award: "100", gain: nil, isVerified: true)
        let current = ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000", platforms: [verified])
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.verify = { _, _, _ in
                Issue.record("The successfully verified account must stay inert")
                return ReclaimStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off
        await store.send(.statusReceived(runID: UUID(0), status: .done(current)))
        await store.send(.dismissRunTapped)
        // Model a response that was already queued when the successful write canceled its read.
        await store.send(.summaryLoaded(ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0"), revision: 0))
        await store.send(.loadFailed(revision: 0))
        #expect(store.state.platforms == [verified])
        #expect(!store.state.isLoading)
        #expect(store.state.errorMessage == nil)
        await store.send(.platformTapped("LinkedIn"))
        #expect(store.state.run == nil)
    }

    // MARK: - The selfie check

    @MainActor @Test func theSelfieRowFollowsTheStanding() async {
        let unverified = LivenessStandingModel(isVerified: false, limitMicros: "0", tierCapMicros: "20000000")
        let store = await listStore(liveness: unverified)
        await store.send(.onAppear)
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }
            $0.liveness = unverified
        }

        let mainnet = await listStore(liveness: nil)
        await mainnet.send(.onAppear)
        await mainnet.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }
        }
        #expect(mainnet.state.liveness == nil)
    }

    @MainActor @Test func aSelfieRunFollowsTheTapNotTheDriverIntoVerifying() async throws {
        let verified = LivenessStandingModel(isVerified: true, limitMicros: "20000000", tierCapMicros: "20000000")
        let statuses = AsyncThrowingStream<LivenessStatusModel, Error>.makeStream()
        let nonces = LockIsolated<[String]>([])
        let store = await selfieStore { currency, nonce, _ in
            #expect(currency == "INR")
            nonces.withValue { $0.append(nonce) }
            return statuses.stream
        }

        await store.send(.selfieTapped) {
            $0.run = selfieRun(stage: .preparing)
        }
        statuses.continuation.yield(.ready(widgetURL: "https://liveness.invalid/w/abc", expiresInSeconds: 600))
        await store.receive(\.livenessStatusReceived) {
            $0.run?.stage = .ready
            $0.run?.launchURL = "https://liveness.invalid/w/abc"
        }
        // The driver says verifying at once; the screen does not follow until the browser opened.
        statuses.continuation.yield(.verifying)
        await store.receive(\.livenessStatusReceived)
        #expect(store.state.run?.stage == .ready)

        let id = try #require(store.state.run?.id)
        await store.send(.verifierOpened(runID: id, accepted: false))
        await store.send(.verifierOpened(runID: id, accepted: true)) {
            $0.run?.isWidgetOpened = true
            $0.run?.stage = .verifying
            $0.lastActiveStage = .verifying
        }

        statuses.continuation.yield(.submitting)
        await store.receive(\.livenessStatusReceived) {
            $0.run?.stage = .submitting
            $0.lastActiveStage = .submitting
        }
        statuses.continuation.yield(.done(verified))
        await store.receive(\.livenessStatusReceived) {
            $0.run?.stage = .done
            $0.run?.newBuyLimitMicros = "20000000"
            $0.summaryRevision = 1
            $0.liveness = verified
        }
        statuses.continuation.finish()
        await store.receive(\.runEnded)

        #expect(nonces.value.count == 1)
        #expect(store.state.steps.allSatisfy { $0.status == .completed })
        #expect(store.state.steps.map(\.label).first == String(localizable: .increaseReputationLivenessStepOpen))
    }

    @MainActor @Test func aReturnWhileTheSelfieRunIsLiveIsDeliveredToIt() async {
        let statuses = AsyncThrowingStream<LivenessStatusModel, Error>.makeStream()
        let delivered = LockIsolated<[LivenessReturnModel]>([])
        let store = await selfieStore(verify: { _, _, _ in statuses.stream }) {
            $0.liveness.deliverReturn = { ret in
                delivered.withValue { $0.append(ret) }
                return true
            }
            $0.liveness.resume = { _, _ in
                Issue.record("a live run must take its own return, never a resume")
                return LivenessStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.selfieTapped)
        statuses.continuation.yield(.ready(widgetURL: "https://liveness.invalid/w/abc", expiresInSeconds: 600))
        await store.receive(\.livenessStatusReceived)

        let ret = LivenessReturnModel(code: "one-time", error: nil, state: "nonce.INR")
        await store.send(.livenessReturnReceived(ret))
        await store.finish()
        #expect(delivered.value == [ret])

        statuses.continuation.finish()
        await store.receive(\.runEnded)
    }

    /// Opening the browser counts as done on a resume, so a failure lands on the selfie step.
    @MainActor @Test func aReturnWithNoLiveRunIsResumed() async {
        let resumed = LockIsolated<[LivenessReturnModel]>([])
        let store = await selfieStore(verify: { _, _, _ in LivenessStatusStream { $0.finish() } }) {
            $0.liveness.resume = { ret, _ in
                resumed.withValue { $0.append(ret) }
                return LivenessStatusStream { continuation in
                    continuation.yield(.verifying)
                    continuation.yield(.failed(.notLive))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let ret = LivenessReturnModel(code: "one-time", error: nil, state: "nonce.INR")
        await store.send(.livenessReturnReceived(ret))
        await store.receive(\.livenessStatusReceived)
        await store.receive(\.livenessStatusReceived)
        await store.receive(\.runEnded)

        #expect(resumed.value == [ret])
        #expect(store.state.run?.isSelfie == true)
        #expect(store.state.run?.errorMessage == String(localizable: .increaseReputationLivenessErrorNotLive))
        let steps = store.state.steps
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .failed)
    }

    @MainActor @Test func aReturnWhileAReclaimRunOwnsTheScreenIsIgnored() async {
        var state = IncreaseReputation.State.initial(currencyCode: "INR")
        state.isLoading = false
        state.run = run(stage: .verifying)
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.liveness.deliverReturn = { _ in Issue.record("delivered over a Reclaim run"); return false }
            $0.liveness.resume = { _, _ in
                Issue.record("resumed over a Reclaim run")
                return LivenessStatusStream { $0.finish() }
            }
        }

        await store.send(.livenessReturnReceived(LivenessReturnModel(code: "one-time", error: nil, state: "nonce.INR")))
        #expect(store.state.run?.platformID == "LinkedIn")
    }

    @MainActor @Test func cancellingInTheWidgetClearsTheRunQuietly() async {
        let store = await selfieStore { _, _, _ in
            LivenessStatusStream { continuation in
                continuation.yield(.ready(widgetURL: "https://liveness.invalid/w/abc", expiresInSeconds: 600))
                continuation.yield(.failed(.cancelled))
                continuation.finish()
            }
        }
        store.exhaustivity = .off

        await store.send(.selfieTapped)
        await store.receive(\.livenessStatusReceived)
        await store.receive(\.livenessStatusReceived)
        await store.receive(\.runEnded)

        #expect(store.state.run == nil)
        #expect(store.state.errorMessage == nil)
    }

    @MainActor @Test func aColdStartResumesTheReturnItWasRebuiltFromExactlyOnce() async {
        let resumed = LockIsolated(0)
        let ret = LivenessReturnModel(code: "one-time", error: nil, state: "nonce.INR")
        let state = IncreaseReputation.State.initial(currencyCode: "INR", resumeLivenessReturn: ret)
        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.uuid = .incrementing
            $0.reputation.summary = { _ in
                ReputationFixtures.summary(
                    canBuy: false,
                    buyLimitMicros: "0",
                    liveness: LivenessStandingModel(isVerified: false, limitMicros: "0", tierCapMicros: "20000000")
                )
            }
            $0.liveness.resume = { _, _ in
                resumed.withValue { $0 += 1 }
                return LivenessStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.finish()
        #expect(resumed.value == 1)
        #expect(store.state.resumeLivenessReturn == nil)
        #expect(store.state.run?.isSelfie == true)
        await store.send(.onAppear)
        await store.finish()
        #expect(resumed.value == 1)
    }

    /// A return that no run could take is dropped, not kept for a later appearance to replay spent.
    @MainActor @Test func aReturnARunCannotTakeIsClearedRatherThanKept() async {
        var state = IncreaseReputation.State.initial(
            currencyCode: "INR",
            resumeLivenessReturn: LivenessReturnModel(code: "one-time", error: nil, state: "nonce.INR")
        )
        state.run = run(stage: .verifying)
        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.liveness.resume = { _, _ in
                Issue.record("a return must never be resumed over a live run")
                return LivenessStatusStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        #expect(store.state.resumeLivenessReturn == nil)
        await store.send(.dismissRunTapped)
        await store.send(.onAppear)
        await store.finish()
        #expect(store.state.run == nil)
    }

    @MainActor @Test func tappingAVerifiedSelfieRowStartsNothing() async {
        var state = IncreaseReputation.State.initial(currencyCode: "INR")
        state.isLoading = false
        state.liveness = LivenessStandingModel(isVerified: true, limitMicros: "20000000", tierCapMicros: "20000000")
        let store = await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.liveness.verify = { _, _, _ in Issue.record("a verified row opened a session"); throw Failure.wrong }
        }

        await store.send(.selfieTapped)
        #expect(store.state.run == nil)
    }

    // MARK: - Helpers

    @MainActor @Test(arguments: [IdentityCheckModel.liveness, .passport])
    func identityCompletionRefreshesReputationAndDuplicateTapsStartOnlyOneRun(_ check: IdentityCheckModel) async {
        var state = IncreaseReputation.State.initial(currencyCode: "BRL")
        state.isLoading = false
        state.identityChecks = [ReputationFixtures.platform(id: check.rawValue, award: "75", gain: "75000000")]
        let statuses = AsyncThrowingStream<LivenessStatusModel, Error>.makeStream()
        let starts = LockIsolated(0)
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.uuid = .incrementing
            $0.liveness.verifyIdentity = { actual, currency, nonce, _ in
                #expect(actual == check)
                #expect(currency == "BRL")
                #expect(!nonce.isEmpty)
                starts.withValue { $0 += 1 }
                return statuses.stream
            }
        }
        store.exhaustivity = .off
        await store.send(.identityTapped(check))
        await store.send(.identityTapped(check))
        statuses.continuation.yield(.submitting)
        await store.receive(\.livenessStatusReceived)
        #expect(starts.value == 1)
        let summary = ReputationFixtures.summary(canBuy: true, buyLimitMicros: "175000000")
        statuses.continuation.yield(.identityDone(summary))
        await store.receive(\.livenessStatusReceived)
        #expect(store.state.run?.stage == .done)
        #expect(store.state.run?.newBuyLimitMicros == "175000000")
        #expect(store.state.run?.newPoints == summary.points)
        statuses.continuation.finish()
        await store.receive(\.runEnded)
    }

    @MainActor @Test func dismissalInvalidatesWaitingSessionThroughDependency() async {
        var state = IncreaseReputation.State.initial(currencyCode: "BRL")
        let id = UUID()
        state.run = .init(id: id, kind: .passport, name: "Passport", stage: .verifying)
        let cancelled = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.liveness.cancel = { check, currency, runID in
                #expect(check == .passport)
                #expect(currency == "BRL")
                cancelled.withValue { $0.append(runID) }
            }
        }
        await store.send(.onDisappear) { $0.run = nil }
        await store.finish()
        #expect(cancelled.value == [id])
    }

    @MainActor @Test func retryUsesIdentityRecoveryEntryPointWithoutReplayingCallback() async {
        var state = IncreaseReputation.State.initial(currencyCode: "BRL")
        state.run = .init(id: UUID(), kind: .passport, name: "Passport", stage: .failed)
        let calls = LockIsolated<[IdentityCheckModel]>([])
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.uuid = .incrementing
            $0.liveness.verifyIdentity = { check, _, _, _ in
                calls.withValue { $0.append(check) }
                return AsyncThrowingStream { $0.yield(.failed(.network)); $0.finish() }
            }
            $0.liveness.resume = { _, _ in Issue.record("Retry replayed redemption callback"); throw Failure.wrong }
        }
        store.exhaustivity = .off
        await store.send(.retryRunTapped)
        await store.receive(\.livenessStatusReceived)
        await store.receive(\.runEnded)
        #expect(calls.value == [.passport])
        #expect(store.state.run?.stage == .failed)
    }

    @MainActor @Test func openingScreenRecoversPersistedPassportWithoutAnotherCallback() async {
        let checks = LockIsolated<[IdentityCheckModel]>([])
        let store = TestStore(initialState: IncreaseReputation.State.initial(currencyCode: "INR")) {
            IncreaseReputation()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
            $0.liveness.recoverable = { currency in
                #expect(currency == "INR")
                return .passport
            }
            $0.liveness.verifyIdentity = { check, _, _, _ in
                checks.withValue { $0.append(check) }
                return AsyncThrowingStream {
                    $0.yield(.identityDone(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "225000000")))
                    $0.finish()
                }
            }
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.recoveryLoaded)
        await store.receive(\.livenessStatusReceived)
        await store.receive(\.runEnded)
        #expect(checks.value == [.passport])
        #expect(store.state.run?.kind == .passport)
        #expect(store.state.run?.newBuyLimitMicros == "225000000")
        #expect(store.state.run?.stage == .done)
    }

    @MainActor @Test func delayedCancellationCannotCancelANewerRun() async {
        var state = IncreaseReputation.State.initial(currencyCode: "BRL")
        state.run = .init(id: UUID(99), kind: .passport, name: "Passport", stage: .verifying)
        state.identityChecks = [ReputationFixtures.platform(id: "Liveness", award: "75", gain: "75000000")]
        let cancelling = AsyncStream<Void>.makeStream()
        var cancellingIterator = cancelling.stream.makeAsyncIterator()
        let release = AsyncStream<Void>.makeStream()
        let statuses = AsyncThrowingStream<LivenessStatusModel, Error>.makeStream()
        let store = TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.uuid = .incrementing
            $0.liveness.cancel = { _, _, runID in
                #expect(runID == UUID(99))
                cancelling.continuation.yield(())
                for await _ in release.stream { break }
            }
            $0.liveness.verifyIdentity = { _, _, _, _ in statuses.stream }
        }
        store.exhaustivity = .off
        let cancellation = await store.send(.cancelRunTapped)
        await cancellingIterator.next()
        await store.send(.identityTapped(.liveness))
        statuses.continuation.yield(.ready(widgetURL: "https://widget.example/new", expiresInSeconds: 1800))
        await store.receive(\.livenessStatusReceived)
        release.continuation.yield(())
        release.continuation.finish()
        await cancellation.finish()
        statuses.continuation.yield(.identityDone(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "325000000")))
        await store.receive(\.livenessStatusReceived)
        #expect(store.state.run?.newBuyLimitMicros == "325000000")
        statuses.continuation.finish()
        await store.receive(\.runEnded)
    }

    private enum Failure: Error { case wrong }

    private func run(stage: IncreaseReputation.State.Stage) -> IncreaseReputation.State.Run {
        IncreaseReputation.State.Run(id: UUID(0), kind: .social(platformID: "LinkedIn"), name: "LinkedIn", stage: stage)
    }

    private func selfieRun(stage: IncreaseReputation.State.Stage) -> IncreaseReputation.State.Run {
        IncreaseReputation.State.Run(
            id: UUID(0),
            kind: .selfie,
            name: String(localizable: .increaseReputationLivenessRow),
            stage: stage
        )
    }

    @MainActor private func listStore(
        currencyCode: String = "INR",
        liveness: LivenessStandingModel? = nil
    ) async -> TestStoreOf<IncreaseReputation> {
        await TestStore(initialState: .initial(currencyCode: currencyCode)) { IncreaseReputation() }
        withDependencies: {
            $0.reputation.summary = { _ in
                ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0", liveness: liveness)
            }
        }
    }

    /// A loaded INR list with an unverified selfie row, and `verify` wired to the given stream.
    @MainActor private func selfieStore(
        verify: @escaping @Sendable (String, String, UUID) async throws -> LivenessStatusStream,
        extra: @escaping (inout DependencyValues) -> Void = { _ in }
    ) async -> TestStoreOf<IncreaseReputation> {
        var state = IncreaseReputation.State.initial(currencyCode: "INR")
        state.isLoading = false
        state.platforms = ReputationFixtures.platforms.filter { $0.id != "Binance" }
        state.liveness = LivenessStandingModel(isVerified: false, limitMicros: "0", tierCapMicros: "20000000")
        return await TestStore(initialState: state) { IncreaseReputation() } withDependencies: {
            $0.uuid = .incrementing
            $0.liveness.verify = verify
            extra(&$0)
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
            $0.uuid = .incrementing
            $0.reputation.verify = { _, _, _ in
                ReclaimStatusStream { continuation in
                    statuses.forEach { continuation.yield($0) }
                    continuation.finish()
                }
            }
            extra(&$0)
        }
    }
}
