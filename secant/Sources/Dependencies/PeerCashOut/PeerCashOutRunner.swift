// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZappOfframp

/// One cash-out attempt as this process knows it. `statuses` is the whole history, oldest first, so
/// a screen that appears after the work started still sees how it got there rather than only where
/// it is.
struct PeerRun: Equatable, Identifiable, Sendable {
    let id: String
    let destinationCode: String
    let amount: UsdcAmount
    let currencyCodes: [String]
    let startedAt: Date
    var statuses: [PeerProgress] = []
    /// Whether this process is driving the attempt right now, rather than merely remembering it.
    var isDriving = false
    /// The deposit a later reconciliation matched to this attempt. An attempt whose submission
    /// outcome was never known carries no status naming one, so without this its amount stays
    /// reserved alongside the order it turned out to open.
    var reconciledDepositID: String?

    var latest: PeerProgress? { statuses.last }

    var depositID: String? { statuses.reversed().compactMap(\.depositID).first ?? reconciledDepositID }

    var failure: PeerFailure? { latest?.failure }

    /// True until the order exists on chain, which is exactly while no indexer list can show it.
    var isUnindexed: Bool { depositID == nil }

    /// Whether this attempt still has a claim on the smart account's USDC. A failure before the
    /// deposit was ever broadcast released nothing; from `creatingDeposit` onward a send may have
    /// landed, so the amount stays committed until it is reconciled — unless the failure itself
    /// proves the escrow took nothing, which a reverted send does.
    var holdsFunds: Bool {
        if depositID != nil { return false }
        guard let failure else { return true }
        return statuses.contains { $0.kind == .creatingDeposit } && !failure.nothingEscrowed
    }
}

/// A withdrawal or a matching toggle, and how far it has got. It outlives the screen that asked for
/// it: the operation is with the bundler either way, and a second tap on re-entry would send twice.
struct PeerOrderAction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case withdraw
        case setAccepting
    }

    let depositID: String
    let kind: Kind
    var latest: PeerProgress?
    var isRunning: Bool
    /// When the action stopped changing the escrow. Nil while it still is.
    var settledAt: Date?

    var failure: PeerFailure? { latest?.failure }

    /// Whether the screen must keep its actions disabled. A settled action has already moved the
    /// escrow while the figures on screen still come from an earlier poll, so releasing the button
    /// before a later read lands offers an action the visible numbers cannot back.
    func awaitsConfirmation(orderReadAt: Date?) -> Bool {
        if isRunning { return true }
        guard let settledAt else { return false }
        guard let orderReadAt else { return true }
        return orderReadAt < settledAt
    }
}

struct PeerRunnerState: Equatable, Sendable {
    static let empty = PeerRunnerState()

    /// Oldest first, so the list does not reorder itself while an attempt is running.
    var runs: [PeerRun] = []
    var orderActions: [String: PeerOrderAction] = [:]

    func run(id: String) -> PeerRun? { runs.first { $0.id == id } }

    /// USDC promised to attempts this process is carrying that have not escrowed it yet.
    var committedByRuns: UsdcAmount { UsdcAmount.sum(runs.filter(\.holdsFunds).map(\.amount)) }
}

/// Owns the work that drives a cash-out from Continue to a live order, on an app-lifetime actor
/// rather than a screen's effect: "the screen is visible" and "the transfer is running" are not the
/// same fact, and a dismissal that cancelled a `createDeposit` mid-flight would leave the user with
/// an escrow the app has no record of.
///
/// Withdrawals and matching toggles run here for the same reason — the UserOperation is with the
/// bundler by the time the screen goes away — so both surfaces read one state.
///
/// Several attempts run at once, each keyed by its own id, because the protocol allows it and a
/// single anonymous slot cannot say which attempt a transaction hash belongs to.
actor PeerCashOutRunner {
    private var client: ApplePeerCashOutClient?
    private var state = PeerRunnerState.empty
    private var jobs: [String: Task<Void, Never>] = [:]
    private var actionJobs: [String: Task<Void, Never>] = [:]
    /// What each attempt was actually asked to do. A retry reads its payee from here rather than
    /// from the rail's current handle, which is not necessarily the one this attempt was opened for.
    private var drafts: [String: PeerCashOutDraft] = [:]
    private var observers: [UUID: AsyncStream<PeerRunnerState>.Continuation] = [:]

    /// Bumped by ``reset()``. Every launch reads it before starting and again once it resumes, so a
    /// task parked on an await cannot wake up and start driving a wallet that has been replaced.
    private var generation = 0

    var currentState: PeerRunnerState { state }

    /// Publishes the current state immediately, then every change. Several screens observe at once,
    /// so each subscriber gets its own continuation rather than sharing one.
    func observe() -> AsyncStream<PeerRunnerState> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(state)
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    /// Adopts the wallet session's Peer client, and picks up whatever the last process left behind:
    /// attempts with a durable record but nothing driving them, plus the reconciliation that tells
    /// the ones that already settled to stop reserving their amount.
    ///
    /// Deliberately does not start driving them. Everything a stored attempt needs is a read, and
    /// the one operation that would write — finishing a funding bridge — cannot exist here, because
    /// iOS has never had a Peer rail to start one.
    func bind(_ client: ApplePeerCashOutClient) async {
        guard self.client !== client else { return }
        await reset()
        self.client = client
        await hydrate()
    }

    /// Cancels and joins everything before the caller erases wallet-scoped storage. Joining rather
    /// than merely cancelling is what stops an in-flight status writing a checkpoint into a file the
    /// wipe has already cleared.
    func reset() async {
        generation &+= 1
        let running = Array(jobs.values) + Array(actionJobs.values)
        running.forEach { $0.cancel() }
        jobs.removeAll()
        actionJobs.removeAll()
        drafts.removeAll()
        client = nil
        publish(.empty)
        for job in running {
            await job.value
        }
    }

    /// A 16-byte identity minted before anything is stored, so the attempt has a name from the
    /// moment the user commits and keeps it through to settlement.
    func newAttemptID(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<byteCount)
            .map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// Claims the reservation on the caller's turn, before anything suspends. The amount screen
    /// validates against a balance with committed attempts already subtracted, so a reservation
    /// nobody can observe yet is what lets a second tap spend the same coins.
    ///
    /// Returns nil when that attempt is already running, which makes a repeat call harmless.
    func start(id: String, draft: PeerCashOutDraft) -> String? {
        guard state.run(id: id) == nil else { return nil }
        var next = state
        next.runs.append(
            PeerRun(
                id: id,
                destinationCode: draft.destinationCode,
                amount: draft.amount,
                currencyCodes: draft.currencyCodes,
                startedAt: Date()
            )
        )
        publish(next)
        drafts[id] = draft
        launchDrive(id: id) { client in client.run(request: draft.apple(attemptID: id)) }
        return id
    }

    /// Resolves what a stored record says was already broadcast, and sends nothing.
    ///
    /// That is a property of the record, not a promise made here: a checkpoint is only written once
    /// it has something to resolve, so every stored attempt resumes into a receipt read, an indexer
    /// lookup or an order poll. The one resume action that would send — finishing a funding bridge —
    /// cannot exist on iOS, where a cash-out never starts one.
    ///
    /// Because it cannot move funds it needs no authentication, which is what makes it safe to run
    /// on every entry to the progress screen and on the cold start after the process died.
    func recover(id: String) {
        launch(id: id) { $0.resume(attemptId: id) }
    }

    /// The user's explicit retry. An attempt that failed before writing a checkpoint has no stored
    /// record to resolve, and its draft is the only thing that can describe it — so this one may
    /// broadcast, and callers authenticate first. Where a checkpoint does exist the facade prefers
    /// it, so a retry still cannot re-send what was already sent.
    func retry(id: String) {
        guard let draft = drafts[id] else { return recover(id: id) }
        launch(id: id) { $0.run(request: draft.apple(attemptID: id)) }
    }

    /// A no-op while the attempt is already running, and for one that reached the chain: from there
    /// its order is the record, and a second pass through setup would escrow a second lot of USDC.
    private func launch(
        id: String,
        operation: @escaping @Sendable (ApplePeerCashOutClient) -> SkieSwiftFlow<ApplePeerStatus>
    ) {
        guard jobs[id] == nil, let run = state.run(id: id), run.depositID == nil else { return }
        mutate(id: id) { $0.statuses.removeAll() }
        launchDrive(id: id, operation: operation)
    }

    func withdraw(depositID: String, amount: UsdcAmount) {
        runOrderAction(depositID: depositID, kind: .withdraw) { client in
            client.withdraw(depositIdComposite: depositID, amountMicros: amount.microsString)
        }
    }

    func setAcceptingIntents(depositID: String, accepting: Bool) {
        runOrderAction(depositID: depositID, kind: .setAccepting) { client in
            client.setAcceptingIntents(depositIdComposite: depositID, accepting: accepting)
        }
    }

    /// Drops a finished action's record, so its error stops outliving the state it described.
    func clearOrderAction(depositID: String) {
        guard state.orderActions[depositID]?.isRunning != true else { return }
        var next = state
        next.orderActions[depositID] = nil
        publish(next)
    }

    /// Matches stored attempts to the orders they turned out to open. Attempts this process is
    /// driving own their own checkpoints and are excluded, because a resume running inside this read
    /// writes hashes that stamping would overwrite with a copy taken before they existed.
    func reconcile() async {
        guard let client else { return }
        let driving = state.runs.filter(\.isDriving).map(\.id)
        guard let matches = try? await client.reconcile(drivingAttemptIds: driving) else { return }
        for match in matches {
            mutate(id: match.attemptId) { run in
                guard !run.isDriving, run.depositID == nil else { return }
                run.reconciledDepositID = match.depositIdComposite
            }
        }
    }

    /// Attempts with a durable record that this process is not carrying. They are what keeps a
    /// cash-out visible after a cold start: the indexer cannot show an order that does not exist
    /// yet, and without these the amount stays subtracted from the balance with nothing to explain
    /// it and no route back.
    private func hydrate() async {
        guard let client else { return }
        let startedIn = generation
        let stored = (try? await client.attempts()) ?? []
        guard startedIn == generation else { return }
        var next = state
        for attempt in stored where attempt.holdsUnescrowedFunds && next.run(id: attempt.id) == nil {
            next.runs.append(
                PeerRun(
                    id: attempt.id,
                    destinationCode: attempt.platformCode,
                    amount: UsdcAmount(micros: attempt.amountMicros) ?? .zero,
                    currencyCodes: attempt.currencyCodes,
                    startedAt: Date(timeIntervalSince1970: TimeInterval(attempt.createdAtEpochSeconds))
                )
            )
        }
        next.runs.sort { $0.startedAt < $1.startedAt }
        publish(next)
        await reconcile()
    }

    /// Stops when the flow completes, which the facade arranges at the live order: from there the
    /// chain is the record and the order screen is the surface. The run itself is kept so the
    /// progress screen can still be re-entered.
    private func launchDrive(
        id: String,
        operation: @escaping @Sendable (ApplePeerCashOutClient) -> SkieSwiftFlow<ApplePeerStatus>
    ) {
        guard let client else { return }
        let startedIn = generation
        mutate(id: id) { $0.isDriving = true }
        jobs[id] = Task { [weak self] in
            for await status in operation(client) {
                guard !Task.isCancelled else { break }
                await self?.record(id: id, status: PeerProgress(status), generation: startedIn)
            }
            await self?.finishDrive(id: id, generation: startedIn)
        }
    }

    private func record(id: String, status: PeerProgress, generation: Int) {
        guard generation == self.generation else { return }
        mutate(id: id) { $0.statuses.append(status) }
    }

    private func finishDrive(id: String, generation: Int) {
        guard generation == self.generation else { return }
        jobs[id] = nil
        mutate(id: id) { $0.isDriving = false }
    }

    /// Claimed before anything suspends, so a second tap while one is live is dropped rather than
    /// queued: the first send is already with the bundler and the second would move the escrow again.
    private func runOrderAction(
        depositID: String,
        kind: PeerOrderAction.Kind,
        operation: @escaping @Sendable (ApplePeerCashOutClient) -> SkieSwiftFlow<ApplePeerStatus>
    ) {
        guard let client, state.orderActions[depositID]?.isRunning != true else { return }
        let startedIn = generation
        var next = state
        next.orderActions[depositID] = PeerOrderAction(depositID: depositID, kind: kind, isRunning: true)
        publish(next)
        actionJobs[depositID] = Task { [weak self] in
            for await status in operation(client) {
                guard !Task.isCancelled else { break }
                await self?.recordAction(depositID: depositID, status: PeerProgress(status), generation: startedIn)
            }
            await self?.settleAction(depositID: depositID, generation: startedIn)
        }
    }

    private func recordAction(depositID: String, status: PeerProgress, generation: Int) {
        guard generation == self.generation else { return }
        mutateAction(depositID: depositID) { $0.latest = status }
    }

    /// A finished action is stamped rather than dropped: the order poll has not caught up and the
    /// screen needs something to hold its buttons closed until it does. A failure keeps its reason
    /// too, because the poll shows the same numbers either way and only the error says why.
    private func settleAction(depositID: String, generation: Int) {
        guard generation == self.generation else { return }
        actionJobs[depositID] = nil
        mutateAction(depositID: depositID) {
            $0.isRunning = false
            $0.settledAt = Date()
        }
    }

    private func mutate(id: String, _ body: (inout PeerRun) -> Void) {
        guard let index = state.runs.firstIndex(where: { $0.id == id }) else { return }
        var next = state
        body(&next.runs[index])
        publish(next)
    }

    private func mutateAction(depositID: String, _ body: (inout PeerOrderAction) -> Void) {
        guard var action = state.orderActions[depositID] else { return }
        body(&action)
        var next = state
        next.orderActions[depositID] = action
        publish(next)
    }

    private func publish(_ next: PeerRunnerState) {
        guard next != state else { return }
        state = next
        observers.values.forEach { $0.yield(next) }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}

/// What the user chose on the amount screen, carried until the attempt settles so a retry repeats
/// the order it was opened for rather than whatever the rail's field holds now.
struct PeerCashOutDraft: Equatable, Sendable {
    let destinationCode: String
    let handle: String
    let currencyCodes: [String]
    let amount: UsdcAmount

    func apple(attemptID: String) -> ApplePeerCashOutRequest {
        ApplePeerCashOutRequest(
            attemptId: attemptID,
            platformCode: destinationCode,
            handle: handle,
            currencyCodes: currencyCodes,
            amountMicros: amount.microsString
        )
    }
}
