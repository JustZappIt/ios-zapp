// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

private final class OfframpSessionWork: @unchecked Sendable {
    private let cancelAction: @Sendable () -> Void
    private let waitAction: @Sendable () async -> Void

    init<Success: Sendable>(_ task: Task<Success, Error>) {
        cancelAction = { task.cancel() }
        waitAction = { _ = await task.result }
    }

    func cancel() { cancelAction() }
    func wait() async { await waitAction() }
}

private struct OfframpUncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

/// One wallet-scoped P2P session. Cash-out, buy, refund and top-up all move USDC from the same
/// Base smart account, so every rail is built on one `AppleBaseAccount` and therefore shares the
/// single ERC-4337 submitter that account's nonce cursor lives in.
///
/// Construction is single-flight. These builders suspend long before they can cache anything, and
/// an actor admits other callers while they do, so caching the in-flight task — not just its
/// result — is what keeps a screen's concurrent loads from each building their own client.
actor OfframpSession {
    static let shared = OfframpSession()

    private func recoveryOperationID(for generation: Int) -> String {
        "durable-recovery-\(generation)"
    }

    private struct OfframpRail {
        let client: AppleOfframpClient
        let bridge: OfframpNearBridge?

        func release() { bridge?.invalidate() }
    }

    private struct OnrampRail {
        let client: AppleOnrampClient
        let gateway: OnrampZecSwapGateway?

        func release() { gateway?.invalidate() }
    }

    private struct BaseReservationSnapshot: Sendable {
        let scanAndPayMicros: String?
        let refundMicros: String?
        let onrampDeliveryMicros: String?
    }

    /// App-lifetime owners of shared Base commitments and Peer's running work. Both outlive every
    /// screen and are reset only at the wallet/account boundary.
    let baseUSDCReservations: BaseUSDCReservationLedger
    let peerRunner: PeerCashOutRunner

    private var account: AppleBaseAccount?
    private var offramp: OfframpRail?
    private var onramp: OnrampRail?
    private var peer: ApplePeerCashOutClient?
    private var accountTask: Task<AppleBaseAccount, Error>?
    private var offrampTask: Task<OfframpRail, Error>?
    private var onrampTask: Task<OnrampRail, Error>?
    private var peerTask: Task<ApplePeerCashOutClient, Error>?
    private var reservationHydrationTask: Task<Void, Error>?
    private var reservationsHydratedGeneration: Int?
    private var stateWritingFlowTasks: [UUID: Task<Void, Never>] = [:]
    private var stateWritingOperations: [UUID: OfframpSessionWork] = [:]
    private var walletIdentity: String?
    private var generation = 0
    private var isInvalidating = false
    private var invalidationWaiters: [CheckedContinuation<Void, Never>] = []

    init(baseUSDCReservations: BaseUSDCReservationLedger = BaseUSDCReservationLedger()) {
        self.baseUSDCReservations = baseUSDCReservations
        self.peerRunner = PeerCashOutRunner(reservations: baseUSDCReservations)
    }

    func client() async throws -> AppleOfframpClient {
        await waitUntilActive()
        return try await offrampRail().client
    }

    func onrampClient() async throws -> AppleOnrampClient {
        await waitUntilActive()
        return try await onrampRail().client
    }

    func peerClient() async throws -> ApplePeerCashOutClient {
        await waitUntilActive()
        let baseSnapshot = try await baseAccountSnapshot()
        try validateGeneration(baseSnapshot.generation)
        if let peerTask { return try await peerTask.value }

        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage

        guard let wallet = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using Peer cash-out.")
        }
        // Peer shares the off-ramp's encrypted file: both rails spend from one Base smart account,
        // so their records are read and written together and a wallet reset clears them together.
        let storage = try OfframpEncryptedStorage(account: wallet.account, walletStorage: walletStorage)
        let generation = baseSnapshot.generation
        let task = Task {
            let built = try await ApplePeerCashOutClient.companion.create(
                account: baseSnapshot.account,
                storage: storage
            )
            guard self.adopt(built, generation: generation) else { throw CancellationError() }
            // Handing the client over is what starts recovery: the runner picks up the attempts a
            // previous process left unfinished and reconciles the ones that already settled.
            await self.peerRunner.bind(built, sessionGeneration: generation)
            return built
        }
        peerTask = task
        return try await value(of: task) { if self.peerTask == task { self.peerTask = nil } }
    }

    /// Releases everything this session adopted. A build still in flight is cancelled and releases
    /// itself when `adopt` turns it away, so nothing is ever torn down twice.
    ///
    /// Peer's runner is cancelled *and joined* before anything else is released, because callers
    /// invalidate immediately before erasing wallet-scoped storage: merely cancelling would let an
    /// in-flight status write a recovery checkpoint into a file the wipe has already cleared.
    func invalidate() async {
        if isInvalidating {
            await withCheckedContinuation { invalidationWaiters.append($0) }
            return
        }
        isInvalidating = true
        generation &+= 1
        walletIdentity = nil
        let accountTask = self.accountTask
        let offrampTask = self.offrampTask
        let onrampTask = self.onrampTask
        let peerTask = self.peerTask
        let reservationHydrationTask = self.reservationHydrationTask
        let stateWritingFlowTasks = Array(self.stateWritingFlowTasks.values)
        let stateWritingOperations = Array(self.stateWritingOperations.values)
        self.accountTask = nil
        self.offrampTask = nil
        self.onrampTask = nil
        self.peerTask = nil
        self.reservationHydrationTask = nil
        reservationsHydratedGeneration = nil
        self.stateWritingFlowTasks.removeAll()
        self.stateWritingOperations.removeAll()

        accountTask?.cancel()
        offrampTask?.cancel()
        onrampTask?.cancel()
        peerTask?.cancel()
        reservationHydrationTask?.cancel()
        stateWritingFlowTasks.forEach { $0.cancel() }
        stateWritingOperations.forEach { $0.cancel() }
        await peerRunner.reset()
        if let accountTask { _ = await accountTask.result }
        if let offrampTask { _ = await offrampTask.result }
        if let onrampTask { _ = await onrampTask.result }
        if let peerTask { _ = await peerTask.result }
        if let reservationHydrationTask { _ = await reservationHydrationTask.result }
        for task in stateWritingFlowTasks { _ = await task.result }
        for operation in stateWritingOperations { await operation.wait() }
        // A Peer builder may have reached `bind` while the first reset was joining. Builders are
        // now fully stopped, so this second join closes that last reentrancy window.
        await peerRunner.reset()
        await baseUSDCReservations.reset()
        onramp?.release()
        offramp?.release()
        onramp = nil
        offramp = nil
        peer = nil
        // The account holds the HTTP client and the Base owner key every rail borrows, so it is last.
        account?.close()
        account = nil
        isInvalidating = false
        let waiters = invalidationWaiters
        invalidationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// Hydrates every durable source before any Base spender is admitted. The Peer runner owns its
    /// own tracked hydration; p2p.me's payment and refund checkpoints are read here in one
    /// generation-checked, single-flight task. A decode or I/O failure deliberately leaves the
    /// source unavailable, because an unreadable record is not evidence that no funds are promised.
    func prepareBaseReservations() async throws {
        await waitUntilActive()
        _ = try await peerClient()
        guard await peerRunner.ensureHydrated() else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        try requireActive()
        let startedIn = generation
        if reservationsHydratedGeneration == startedIn { return }

        let task: Task<Void, Error>
        if let reservationHydrationTask {
            task = reservationHydrationTask
        } else {
            let client = try await offrampRail().client
            try requireActive()
            guard startedIn == generation else { throw CancellationError() }
            // Several callers can enter the outer else while the rail is building. Recheck after
            // that suspension so only the first resumed caller starts the checkpoint reads.
            if let reservationHydrationTask {
                task = reservationHydrationTask
            } else {
                let onrampClient: AppleOnrampClient?
                if let baseURL = PartnerKeys.p2pOnrampBaseUrl,
                   !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onrampClient = try await onrampRail().client
                    try requireActive()
                    guard startedIn == generation else { throw CancellationError() }
                } else {
                    onrampClient = nil
                }
                // Building the optional rail suspends too, so repeat the single-flight check.
                if let reservationHydrationTask {
                    task = reservationHydrationTask
                } else {
                    await baseUSDCReservations.markLoading(.scanAndPay)
                    await baseUSDCReservations.markLoading(.onrampDelivery)
                    task = Task {
                        do {
                            async let scanAndPay = client.pendingBaseCommitmentMicros()
                            async let refund = client.pendingRefundCommitmentMicros()
                            // Awaited here rather than in a third `async let`: the optional rail is
                            // actor-isolated, and an async let child is not. It still overlaps the
                            // two reads above, which are already in flight.
                            let onrampDelivery = try await onrampClient?.pendingBaseCommitmentMicros()
                            let snapshot = try await BaseReservationSnapshot(
                                scanAndPayMicros: scanAndPay,
                                refundMicros: refund,
                                onrampDeliveryMicros: onrampDelivery
                            )
                            try await self.applyBaseReservationSnapshot(snapshot, generation: startedIn)
                        } catch {
                            await self.failBaseReservationHydration(generation: startedIn)
                            throw error
                        }
                    }
                    reservationHydrationTask = task
                }
            }
        }

        do {
            try await task.value
            try validateGeneration(startedIn)
            if reservationHydrationTask == task { reservationHydrationTask = nil }
        } catch {
            if reservationHydrationTask == task { reservationHydrationTask = nil }
            throw error
        }
    }

    private func applyBaseReservationSnapshot(
        _ snapshot: BaseReservationSnapshot,
        generation expectedGeneration: Int
    ) async throws {
        try validateGeneration(expectedGeneration)
        if let micros = snapshot.scanAndPayMicros {
            guard let amount = UsdcAmount(micros: micros), amount.isPositive else {
                throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
            }
            _ = try await baseUSDCReservations.restoreOrFindScanAndPay(
                .scanAndPay(operationID: recoveryOperationID(for: expectedGeneration)),
                amount: amount
            )
        }
        if let micros = snapshot.refundMicros {
            guard let amount = UsdcAmount(micros: micros), amount.isPositive else {
                throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
            }
            _ = try await baseUSDCReservations.restoreOrFindRefund(
                .refund(operationID: recoveryOperationID(for: expectedGeneration)),
                amount: amount
            )
        }
        if let micros = snapshot.onrampDeliveryMicros {
            guard let amount = UsdcAmount(micros: micros), amount.isPositive else {
                throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
            }
            _ = try await baseUSDCReservations.restoreOrFindOnrampDelivery(
                .onrampDelivery(operationID: recoveryOperationID(for: expectedGeneration)),
                amount: amount
            )
        }
        await baseUSDCReservations.markReady(.scanAndPay)
        await baseUSDCReservations.markReady(.onrampDelivery)
        try validateGeneration(expectedGeneration)
        reservationsHydratedGeneration = expectedGeneration
    }

    private func failBaseReservationHydration(generation expectedGeneration: Int) async {
        guard expectedGeneration == generation, !isInvalidating else { return }
        reservationsHydratedGeneration = nil
        await baseUSDCReservations.markUnavailable(.scanAndPay)
        await baseUSDCReservations.markUnavailable(.onrampDelivery)
    }

    func spendableBaseBalance(rawBalance: UsdcAmount) async throws -> PeerSpendableBalance {
        let startedIn = generation
        try await prepareBaseReservations()
        guard startedIn == generation, !isInvalidating else { throw CancellationError() }
        return await baseUSDCReservations.spendable(rawBalance: rawBalance)
    }

    func quote(
        currencyCode: String,
        fiatAmount: String
    ) async throws -> (native: AppleOfframpQuote, spendable: PeerSpendableBalance, generation: Int) {
        let startedIn = try generationToken()
        let client = try await offrampRail().client
        try validateGeneration(startedIn)
        let native = try await client.quote(currencyCode: currencyCode, fiatAmount: fiatAmount)
        guard startedIn == generation, !isInvalidating,
              let rawBalance = UsdcAmount(micros: native.baseBalanceMicros) else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        let spendable = try await spendableBaseBalance(rawBalance: rawBalance)
        guard startedIn == generation, !isInvalidating else { throw CancellationError() }
        return (native, spendable, startedIn)
    }

    func claimScanAndPay(
        _ amount: UsdcAmount,
        quoteGeneration: Int,
        operationID: String
    ) async throws -> BaseUSDCReservationLedger.Owner {
        let startedIn = generation
        guard quoteGeneration == startedIn else { throw OfframpClientError.staleQuote }
        try await prepareBaseReservations()
        let summary = try await offrampRail().client.accountSummary()
        guard quoteGeneration == generation, startedIn == generation, !isInvalidating,
              let micros = summary.balanceMicros, let rawBalance = UsdcAmount(micros: micros) else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        let owner = BaseUSDCReservationLedger.Owner.scanAndPay(operationID: operationID)
        try await baseUSDCReservations.claim(owner, amount: amount, rawBalance: rawBalance)
        return owner
    }

    func startScanAndPay(
        quote: AppleOfframpQuote,
        paymentDetailsProvider: AppleOfframpPaymentDetailsProvider,
        payeeName: String?,
        amount: UsdcAmount,
        quoteGeneration: Int,
        operationID: String
    ) async throws -> AsyncStream<OfframpProgressModel> {
        let owner = try await claimScanAndPay(
            amount,
            quoteGeneration: quoteGeneration,
            operationID: operationID
        )
        do {
            try validateGeneration(quoteGeneration)
            let client = try await offrampRail().client
            try validateGeneration(quoteGeneration)
            let flow = client.pay(
                quote: quote,
                paymentDetailsProvider: paymentDetailsProvider,
                payeeName: payeeName
            )
            return try trackOfframpFlow(
                flow,
                reservation: .scanAndPay(owner),
                generation: quoteGeneration
            )
        } catch {
            // A cold KMP flow has not been collected yet, so this is positive pre-broadcast proof.
            await baseUSDCReservations.settle(owner, as: .available)
            throw error
        }
    }

    /// Nil where the checkpoint no longer holds unescrowed Base USDC. A payment resumed after its
    /// order was placed owns nothing another spender could take, and refusing it would be a dead
    /// end: the checkpoint still blocks a new payment while the resume that would clear it errors.
    func reservationForResumedScanAndPay() async throws -> BaseUSDCReservationLedger.Owner? {
        let startedIn = generation
        try await prepareBaseReservations()
        let pending = try await offrampRail().client.pendingBaseCommitmentMicros()
        guard startedIn == generation, !isInvalidating else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        guard let pending else { return nil }
        guard let amount = UsdcAmount(micros: pending), amount.isPositive else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        return try await baseUSDCReservations.restoreOrFindScanAndPay(
            .scanAndPay(operationID: recoveryOperationID(for: startedIn)),
            amount: amount
        )
    }

    func resumeScanAndPay(
        paymentDetailsProvider: AppleOfframpPaymentDetailsProvider,
        expectedGeneration: Int
    ) async throws -> AsyncStream<OfframpProgressModel> {
        guard expectedGeneration == generation else { throw CancellationError() }
        let owner = try await reservationForResumedScanAndPay()
        try validateGeneration(expectedGeneration)
        let client = try await offrampRail().client
        try validateGeneration(expectedGeneration)
        return try trackOfframpFlow(
            client.resumePayment(paymentDetailsProvider: paymentDetailsProvider),
            reservation: owner.map(OfframpReservation.scanAndPay),
            generation: expectedGeneration
        )
    }

    func claimRefund(
        expectedGeneration: Int
    ) async throws -> (owner: BaseUSDCReservationLedger.Owner, newlyClaimed: Bool) {
        guard expectedGeneration == generation else { throw CancellationError() }
        let startedIn = expectedGeneration
        try await prepareBaseReservations()
        try validateGeneration(startedIn)
        let client = try await offrampRail().client
        try validateGeneration(startedIn)
        // Confirmation rechecks the durable checkpoint. A recovered refund resumes its original
        // exclusive owner; a genuinely new refund receives a unique owner so an equal-amount
        // second request cannot pass as an idempotent claim.
        if let pending = try await client.pendingRefundCommitmentMicros() {
            guard startedIn == generation, !isInvalidating,
                  let amount = UsdcAmount(micros: pending), amount.isPositive else {
                throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
            }
            let owner = try await baseUSDCReservations.restoreOrFindRefund(
                .refund(operationID: recoveryOperationID(for: startedIn)),
                amount: amount
            )
            try validateGeneration(startedIn)
            return (owner, false)
        }
        let summary = try await client.accountSummary()
        guard startedIn == generation, !isInvalidating,
              let micros = summary.balanceMicros, let rawBalance = UsdcAmount(micros: micros) else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        let owner = BaseUSDCReservationLedger.Owner.refund(operationID: UUID().uuidString)
        try await baseUSDCReservations.claimExclusive(owner, rawBalance: rawBalance)
        return (owner, true)
    }

    func recoverFunds(
        orderID: String?,
        expectedGeneration: Int
    ) async throws -> AsyncStream<OfframpProgressModel> {
        guard expectedGeneration == generation else { throw CancellationError() }
        let claim = try await claimRefund(expectedGeneration: expectedGeneration)
        do {
            try validateGeneration(expectedGeneration)
            let client = try await offrampRail().client
            try validateGeneration(expectedGeneration)
            return try trackOfframpFlow(
                client.recoverFunds(orderId: orderID),
                reservation: .refund(claim.owner),
                generation: expectedGeneration
            )
        } catch {
            if claim.newlyClaimed {
                await baseUSDCReservations.settle(claim.owner, as: .available)
            }
            throw error
        }
    }

    func bridgeToBase(
        usdcMicros: String,
        resumeDepositAddress: String?,
        expectedGeneration: Int
    ) async throws -> AsyncStream<OfframpProgressModel> {
        guard expectedGeneration == generation else { throw CancellationError() }
        let client = try await offrampRail().client
        try validateGeneration(expectedGeneration)
        let flow = try await performTracked(generation: expectedGeneration) {
            try await client.bridgeToBase(
                usdcMicros: usdcMicros,
                resumeDepositAddress: resumeDepositAddress
            )
        }
        return try trackOfframpFlow(flow, reservation: nil, generation: expectedGeneration)
    }

    func discardPaymentCheckpoint() async throws {
        let startedIn = try generationToken()
        let client = try await offrampRail().client
        try validateGeneration(startedIn)
        try await performTracked(generation: startedIn) {
            try await client.discardCheckpoint()
        }
    }

    func discardTopUpCheckpoint() async throws {
        let startedIn = try generationToken()
        let client = try await offrampRail().client
        try validateGeneration(startedIn)
        try await performTracked(generation: startedIn) {
            try await client.discardTopUpCheckpoint()
        }
    }

    func settleScanAndPay(
        _ owner: BaseUSDCReservationLedger.Owner,
        as settlement: BaseUSDCReservationLedger.Settlement
    ) async {
        await baseUSDCReservations.settle(owner, as: settlement)
    }

    func settleRefund(
        _ owner: BaseUSDCReservationLedger.Owner,
        as settlement: BaseUSDCReservationLedger.Settlement
    ) async {
        await baseUSDCReservations.settle(owner, as: settlement)
    }

    func settleOnrampDelivery(
        _ owner: BaseUSDCReservationLedger.Owner,
        as settlement: BaseUSDCReservationLedger.Settlement
    ) async {
        await baseUSDCReservations.settle(owner, as: settlement)
    }

    func pendingScanAndPayCommitmentForSettlement() async throws -> String? {
        try requireActive()
        let client = try await offrampRail().client
        try requireActive()
        let pending = try await client.pendingBaseCommitmentMicros()
        try requireActive()
        return pending
    }

    func pendingRefundCommitmentForSettlement() async throws -> String? {
        try requireActive()
        let client = try await offrampRail().client
        try requireActive()
        let pending = try await client.pendingRefundCommitmentMicros()
        try requireActive()
        return pending
    }

    func pendingOnrampCommitmentForSettlement() async throws -> String? {
        try requireActive()
        let client = try await onrampRail().client
        try requireActive()
        let pending = try await client.pendingBaseCommitmentMicros()
        try requireActive()
        return pending
    }

    func startPeerCashOut(
        draft: PeerCashOutDraft,
        attemptIDByteCount: Int,
        expectedGeneration: Int
    ) async throws -> String {
        guard expectedGeneration == generation else { throw CancellationError() }
        try await prepareBaseReservations()
        try validateGeneration(expectedGeneration)
        let client = try await peerClient()
        try validateGeneration(expectedGeneration)
        guard let rawBalance = PeerAccount(try await client.account()).balance else {
            throw PeerCashOutClientError.unavailable
        }
        try validateGeneration(expectedGeneration)
        let id = await peerRunner.newAttemptID(byteCount: attemptIDByteCount)
        guard let started = try await peerRunner.start(
            id: id,
            draft: draft,
            rawBalance: rawBalance,
            sessionGeneration: expectedGeneration
        ) else {
            throw PeerCashOutClientError.unavailable
        }
        try validateGeneration(expectedGeneration)
        return started
    }

    func recoverPeerCashOut(attemptID: String, expectedGeneration: Int) async throws {
        guard expectedGeneration == generation else { throw CancellationError() }
        _ = try await peerClient()
        try validateGeneration(expectedGeneration)
        await peerRunner.recover(id: attemptID, sessionGeneration: expectedGeneration)
    }

    /// Reads the balance the retry is admitted against, exactly as starting one does: a retry that
    /// may broadcast has to pass the same admission check as the first attempt.
    func retryPeerCashOut(attemptID: String, expectedGeneration: Int) async throws {
        guard expectedGeneration == generation else { throw CancellationError() }
        try await prepareBaseReservations()
        try validateGeneration(expectedGeneration)
        let client = try await peerClient()
        try validateGeneration(expectedGeneration)
        guard let rawBalance = PeerAccount(try await client.account()).balance else {
            throw PeerCashOutClientError.unavailable
        }
        try validateGeneration(expectedGeneration)
        try await peerRunner.retry(
            id: attemptID,
            rawBalance: rawBalance,
            sessionGeneration: expectedGeneration
        )
    }

    func withdrawPeerCashOut(
        depositID: String,
        amount: UsdcAmount,
        expectedGeneration: Int
    ) async throws {
        guard expectedGeneration == generation else { throw CancellationError() }
        _ = try await peerClient()
        try validateGeneration(expectedGeneration)
        await peerRunner.withdraw(
            depositID: depositID,
            amount: amount,
            sessionGeneration: expectedGeneration
        )
    }

    func setPeerAcceptingIntents(
        depositID: String,
        accepting: Bool,
        expectedGeneration: Int
    ) async throws {
        guard expectedGeneration == generation else { throw CancellationError() }
        _ = try await peerClient()
        try validateGeneration(expectedGeneration)
        await peerRunner.setAcceptingIntents(
            depositID: depositID,
            accepting: accepting,
            sessionGeneration: expectedGeneration
        )
    }

    func startOnrampOrder(
        quote: AppleOnrampQuote,
        destination: String,
        estimate: AppleOnrampZecEstimate?,
        expectedGeneration: Int
    ) async throws -> OnrampStatusStream {
        guard expectedGeneration == generation else { throw CancellationError() }
        let client = try await onrampRail().client
        try validateGeneration(expectedGeneration)
        let flow = try await performTracked(generation: expectedGeneration) {
            try await client.start(quote: quote, destination: destination, zecEstimate: estimate)
        }
        return try trackOnrampFlow(flow, generation: expectedGeneration)
    }

    func confirmOnrampPaid(expectedGeneration: Int) async throws -> OnrampStatusStream {
        guard expectedGeneration == generation else { throw CancellationError() }
        let client = try await onrampRail().client
        try validateGeneration(expectedGeneration)
        let flow = try await performTracked(generation: expectedGeneration) {
            try await client.confirmPaid()
        }
        return try trackOnrampFlow(flow, generation: expectedGeneration)
    }

    func resumeOnrampOrder(expectedGeneration: Int) async throws -> OnrampStatusStream {
        guard expectedGeneration == generation else { throw CancellationError() }
        let client = try await onrampRail().client
        try validateGeneration(expectedGeneration)
        let flow = try await performTracked(generation: expectedGeneration) {
            try await client.resume()
        }
        return try trackOnrampFlow(flow, generation: expectedGeneration)
    }

    func cancelOnrampOrder(expectedGeneration: Int) async throws -> OnrampStatusStream {
        guard expectedGeneration == generation else { throw CancellationError() }
        let client = try await onrampRail().client
        try validateGeneration(expectedGeneration)
        let flow = try await performTracked(generation: expectedGeneration) {
            try await client.cancel()
        }
        return try trackOnrampFlow(flow, generation: expectedGeneration)
    }

    func deliverOnrampToZec(
        orderID: String,
        recipient: String,
        usdcMicros: String,
        expectedGeneration: Int
    ) async throws -> OnrampDeliveryStream {
        guard expectedGeneration == generation,
              let amount = UsdcAmount(micros: usdcMicros), amount.isPositive else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        try await prepareBaseReservations()
        try validateGeneration(expectedGeneration)
        let client = try await onrampRail().client
        guard try await client.pendingBaseCommitmentMicros() == usdcMicros else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        let rawBalance = try await currentRawBaseBalance(generation: expectedGeneration)
        let owner = BaseUSDCReservationLedger.Owner.onrampDelivery(operationID: UUID().uuidString)
        try await baseUSDCReservations.activateOnrampDelivery(owner, amount: amount, rawBalance: rawBalance)
        do {
            try validateGeneration(expectedGeneration)
            let flow = try await performTracked(generation: expectedGeneration) {
                try await client.deliverToZec(
                    orderId: orderID,
                    recipient: recipient,
                    usdcMicros: usdcMicros
                )
            }
            return try trackOnrampDeliveryFlow(
                flow,
                reservation: .delivery(owner),
                generation: expectedGeneration
            )
        } catch {
            await baseUSDCReservations.settle(owner, as: .available)
            throw error
        }
    }

    func resumeOnrampDelivery(expectedGeneration: Int) async throws -> OnrampDeliveryStream {
        guard expectedGeneration == generation else { throw CancellationError() }
        try await prepareBaseReservations()
        try validateGeneration(expectedGeneration)
        let client = try await onrampRail().client
        let reservation: OnrampReservation?
        if let micros = try await client.pendingBaseCommitmentMicros() {
            guard let amount = UsdcAmount(micros: micros), amount.isPositive else {
                throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
            }
            // Before the write, not after it. This actor can be suspended across the await above
            // while `invalidate()` bumps the generation and resets the ledger, and the restore
            // below would then insert the previous wallet's commitment into the new wallet's
            // freshly reset books. Validating afterwards aborts the call but leaves that phantom
            // reservation behind, depressing the new wallet's available balance — and since the
            // recovery operation id embeds the old generation, the next hydration can find a
            // mismatched sole match and wedge the ledger with `recoveryUnavailable`.
            try validateGeneration(expectedGeneration)
            let owner = try await baseUSDCReservations.restoreOrFindOnrampDelivery(
                .onrampDelivery(operationID: recoveryOperationID(for: expectedGeneration)),
                amount: amount
            )
            reservation = .delivery(owner)
        } else {
            // Exact recovery says the funds already left Base or returned there terminally. The
            // remaining delivery poll cannot contend with another Base spender.
            reservation = nil
        }
        try validateGeneration(expectedGeneration)
        let flow = try await performTracked(generation: expectedGeneration) {
            try await client.resumeDelivery()
        }
        return try trackOnrampDeliveryFlow(
            flow,
            reservation: reservation,
            generation: expectedGeneration
        )
    }

    func retryOnrampDelivery(expectedGeneration: Int) async throws -> OnrampDeliveryStream {
        guard expectedGeneration == generation else { throw CancellationError() }
        try await prepareBaseReservations()
        try validateGeneration(expectedGeneration)
        let client = try await onrampRail().client
        guard let micros = try await client.checkpoint()?.zecDelivery?.usdcMicros,
              let amount = UsdcAmount(micros: micros), amount.isPositive else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        let rawBalance = try await currentRawBaseBalance(generation: expectedGeneration)
        let owner = BaseUSDCReservationLedger.Owner.onrampDelivery(operationID: UUID().uuidString)
        // A retry takes over the interrupted attempt's commitment rather than stacking a second
        // one on top of it. A plain `claim` computes availability as balance minus committed,
        // and the commitment being retried is still in that total, so a delivery interrupted
        // without a terminal status made "Try conversion again" fail with `insufficientAvailable`.
        try await baseUSDCReservations.activateOnrampDelivery(owner, amount: amount, rawBalance: rawBalance)
        do {
            try validateGeneration(expectedGeneration)
            let flow = try await performTracked(generation: expectedGeneration) {
                try await client.retryDelivery()
            }
            return try trackOnrampDeliveryFlow(
                flow,
                reservation: .delivery(owner),
                generation: expectedGeneration
            )
        } catch {
            await baseUSDCReservations.settle(owner, as: .available)
            throw error
        }
    }

    func clearOnrampCheckpoint() async throws {
        let startedIn = try generationToken()
        let client = try await onrampRail().client
        try validateGeneration(startedIn)
        try await performTracked(generation: startedIn) {
            try await client.clearCheckpoint()
        }
    }

    private func currentRawBaseBalance(generation expectedGeneration: Int) async throws -> UsdcAmount {
        let summary = try await offrampRail().client.accountSummary()
        guard expectedGeneration == generation, !isInvalidating,
              let micros = summary.balanceMicros,
              let balance = UsdcAmount(micros: micros) else {
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        return balance
    }

    func trackOfframpFlow(
        _ flow: SkieSwiftFlow<AppleOfframpStatus>,
        reservation: OfframpReservation?,
        generation expectedGeneration: Int
    ) throws -> AsyncStream<OfframpProgressModel> {
        try validateGeneration(expectedGeneration)
        let id = UUID()
        var capturedContinuation: AsyncStream<OfframpProgressModel>.Continuation?
        let stream = AsyncStream<OfframpProgressModel> { continuation in
            capturedContinuation = continuation
        }
        guard let continuation = capturedContinuation else { return stream }
        let task = Task { [weak self] in
            var receivedStatus = false
            var recordedDisposition = false
            for await status in flow {
                guard !Task.isCancelled else { break }
                receivedStatus = true
                let model = OfframpProgressModel(status)
                if await reservation?.record(model) == true { recordedDisposition = true }
                continuation.yield(model)
            }
            if let reservation, !recordedDisposition {
                await reservation.finishInterrupted(receivedStatus: receivedStatus)
            }
            continuation.finish()
            await self?.offrampFlowFinished(id: id)
        }
        stateWritingFlowTasks[id] = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func trackOnrampFlow(
        _ flow: SkieSwiftFlow<AppleOnrampStatus>,
        generation expectedGeneration: Int
    ) throws -> OnrampStatusStream {
        try validateGeneration(expectedGeneration)
        let id = UUID()
        var capturedContinuation: OnrampStatusStream.Continuation?
        let stream = OnrampStatusStream { continuation in capturedContinuation = continuation }
        guard let continuation = capturedContinuation else { return stream }
        let task = Task { [weak self] in
            do {
                for await status in flow {
                    guard !Task.isCancelled else { break }
                    continuation.yield(try OnrampStatusModel(status))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            await self?.stateWritingFlowFinished(id: id)
        }
        stateWritingFlowTasks[id] = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func trackOnrampDeliveryFlow(
        _ flow: SkieSwiftFlow<AppleOnrampDeliveryStatus>,
        reservation: OnrampReservation?,
        generation expectedGeneration: Int
    ) throws -> OnrampDeliveryStream {
        try validateGeneration(expectedGeneration)
        let id = UUID()
        var capturedContinuation: OnrampDeliveryStream.Continuation?
        let stream = OnrampDeliveryStream { continuation in capturedContinuation = continuation }
        guard let continuation = capturedContinuation else { return stream }
        let task = Task { [weak self] in
            var receivedStatus = false
            var recordedDisposition = false
            do {
                for await status in flow {
                    guard !Task.isCancelled else { break }
                    receivedStatus = true
                    let model = try OnrampDeliveryModel(status)
                    if await reservation?.record(model) == true { recordedDisposition = true }
                    continuation.yield(model)
                }
                if let reservation, !recordedDisposition {
                    await reservation.finishInterrupted(receivedStatus: receivedStatus)
                }
                continuation.finish()
            } catch {
                if let reservation, !recordedDisposition {
                    await reservation.finishInterrupted(receivedStatus: receivedStatus)
                }
                continuation.finish(throwing: error)
            }
            await self?.stateWritingFlowFinished(id: id)
        }
        stateWritingFlowTasks[id] = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func offrampFlowFinished(id: UUID) {
        stateWritingFlowFinished(id: id)
    }

    private func stateWritingFlowFinished(id: UUID) {
        stateWritingFlowTasks[id] = nil
    }

    private func performTracked<Success>(
        generation expectedGeneration: Int,
        operation: @escaping @Sendable () async throws -> Success
    ) async throws -> Success {
        try validateGeneration(expectedGeneration)
        let id = UUID()
        let task = Task { OfframpUncheckedSendable(value: try await operation()) }
        stateWritingOperations[id] = OfframpSessionWork(task)
        do {
            let result = try await task.value
            stateWritingOperations[id] = nil
            try validateGeneration(expectedGeneration)
            return result.value
        } catch {
            stateWritingOperations[id] = nil
            throw error
        }
    }

    /// Exercises the same ownership registry as KMP commands without requiring a live wallet.
    /// The regression verifies that invalidation joins cancellation-resistant foreign work.
    func runStateWritingOperationForTesting(
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        let startedIn = try generationToken()
        try await performTracked(generation: startedIn, operation: operation)
    }

    /// Takes ownership of a finished build, or refuses it because the session has moved on to
    /// another wallet since it started. Refusing is what makes the builder release it instead.
    private func adopt(_ built: AppleBaseAccount, generation: Int) -> Bool {
        guard generation == self.generation, !isInvalidating else { return false }
        account = built
        return true
    }

    private func adopt(_ built: OfframpRail, generation: Int) -> Bool {
        guard generation == self.generation, !isInvalidating else { return false }
        offramp = built
        return true
    }

    private func adopt(_ built: OnrampRail, generation: Int) -> Bool {
        guard generation == self.generation, !isInvalidating else { return false }
        onramp = built
        return true
    }

    /// The Peer client borrows the account's HTTP client and submitter and owns nothing of its own,
    /// so a refused build needs no release beyond being dropped.
    private func adopt(_ built: ApplePeerCashOutClient, generation: Int) -> Bool {
        guard generation == self.generation, !isInvalidating else { return false }
        peer = built
        return true
    }

    private func baseAccountSnapshot() async throws -> (account: AppleBaseAccount, generation: Int) {
        let account = try await baseAccount()
        try requireActive()
        return (account, generation)
    }

    private func baseAccount() async throws -> AppleBaseAccount {
        await waitUntilActive()
        var identity = try walletScope()
        // Cross the wallet/network boundary before deriving anything new. This zeroizes the old
        // Base key and cancels bridge work even if the new setup then fails.
        if identity != walletIdentity {
            let hasPreviousSession = walletIdentity != nil ||
                account != nil || accountTask != nil ||
                offramp != nil || offrampTask != nil ||
                onramp != nil || onrampTask != nil ||
                peer != nil || peerTask != nil
            if hasPreviousSession {
                await invalidate()
                // The selected wallet can change again while joined teardown is suspended.
                identity = try walletScope()
            }
        }
        try requireActive()
        walletIdentity = identity
        if let accountTask { return try await accountTask.value }

        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let pimlicoKey = PartnerKeys.p2pPimlicoApiKey, !pimlicoKey.isEmpty else {
            throw OfframpClientError.configuration("P2P payments are not configured in PartnerKeys.plist.")
        }
        let isTestnet = environment.network().networkType == .testnet
        // The KMP facade derives the Base owner directly from this active Zcash wallet mnemonic
        // at m/44'/60'/0'/0/0, matching Android. No separate Base seed or private key is stored.
        let seedPhrase = try walletStorage.exportWallet().seedPhrase.value()
        let generation = self.generation
        let task = Task {
            let built = try await AppleBaseAccount.companion.create(
                networkName: isTestnet ? "sepolia" : "mainnet",
                seedPhrase: seedPhrase,
                pimlicoApiKey: pimlicoKey,
                rpcUrl: isTestnet ? nil : PartnerKeys.p2pRpcBaseMainnet,
                subgraphUrl: isTestnet ? nil : PartnerKeys.p2pSubgraphMainnet,
                sponsorshipPolicyId: PartnerKeys.p2pSponsorshipPolicyId
            )
            guard self.adopt(built, generation: generation) else {
                built.close()
                throw CancellationError()
            }
            return built
        }
        accountTask = task
        return try await value(of: task) { if self.accountTask == task { self.accountTask = nil } }
    }

    private func offrampRail() async throws -> OfframpRail {
        let baseSnapshot = try await baseAccountSnapshot()
        try validateGeneration(baseSnapshot.generation)
        if let offrampTask { return try await offrampTask.value }

        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.swapAndPay) var swapAndPay
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer
        @Dependency(\.mnemonic) var mnemonic
        @Dependency(\.derivationTool) var derivationTool
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let wallet = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using P2P payments.")
        }
        let storage = try OfframpEncryptedStorage(account: wallet.account, walletStorage: walletStorage)
        let bridge: OfframpNearBridge? = environment.network().networkType == .testnet ? nil : OfframpNearBridge(
            account: wallet,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer,
            walletStorage: walletStorage,
            mnemonic: mnemonic,
            derivationTool: derivationTool,
            environment: environment
        )
        let generation = baseSnapshot.generation
        let task = Task {
            let built = OfframpRail(
                client: try await AppleOfframpClient.companion.create(
                    account: baseSnapshot.account,
                    storage: storage,
                    bridge: bridge
                ),
                bridge: bridge
            )
            guard self.adopt(built, generation: generation) else {
                built.release()
                throw CancellationError()
            }
            return built
        }
        offrampTask = task
        return try await value(of: task) { if self.offrampTask == task { self.offrampTask = nil } }
    }

    private func onrampRail() async throws -> OnrampRail {
        let baseSnapshot = try await baseAccountSnapshot()
        try validateGeneration(baseSnapshot.generation)
        if let onrampTask { return try await onrampTask.value }

        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.walletStorage) var walletStorage
        @Dependency(\.swapAndPay) var swapAndPay
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let wallet = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before buying ZEC.")
        }
        guard let baseURL = PartnerKeys.p2pOnrampBaseUrl, !baseURL.isEmpty else {
            throw OfframpClientError.configuration("P2P buying is not configured in PartnerKeys.plist.")
        }
        let storage = try OnrampEncryptedStorage(account: wallet.account, walletStorage: walletStorage)
        let gateway: OnrampZecSwapGateway? = environment.network().networkType == .testnet ? nil : OnrampZecSwapGateway(
            account: wallet,
            swapAndPay: swapAndPay,
            sdkSynchronizer: sdkSynchronizer
        )
        let generation = baseSnapshot.generation
        let task = Task {
            let built = OnrampRail(
                client: try await AppleOnrampClient.companion.create(
                    account: baseSnapshot.account,
                    onrampBaseUrl: baseURL,
                    storage: storage,
                    deviceSignals: OnrampDeviceSignals(),
                    onrampAppId: "zapp",
                    swapGateway: gateway,
                    useFakeDeliveryDriver: false
                ),
                gateway: gateway
            )
            guard self.adopt(built, generation: generation) else {
                built.release()
                throw CancellationError()
            }
            return built
        }
        onrampTask = task
        return try await value(of: task) { if self.onrampTask == task { self.onrampTask = nil } }
    }

    /// Awaits a build, dropping a failed one from the cache so the next caller may try again.
    private func value<T>(of task: Task<T, Error>, onFailure evict: () -> Void) async throws -> T {
        do {
            return try await task.value
        } catch {
            evict()
            throw error
        }
    }

    private func requireActive() throws {
        guard !isInvalidating else { throw CancellationError() }
    }

    private func waitUntilActive() async {
        while isInvalidating {
            await withCheckedContinuation { invalidationWaiters.append($0) }
        }
    }

    func generationToken() throws -> Int {
        try requireActive()
        return generation
    }

    func validateGeneration(_ expected: Int) throws {
        try requireActive()
        guard expected == generation else { throw CancellationError() }
    }

    /// The wallet lifetime a session belongs to. The account UUID alone is not a sufficient
    /// boundary, so the SDK seed fingerprint is included: a delete and restore in the same process
    /// can then never retain the prior wallet's Base owner. The mnemonic is never a cache key.
    private func walletScope() throws -> String {
        @Shared(.inMemory(.selectedWalletAccount)) var selectedAccount: WalletAccount?
        @Dependency(\.zcashSDKEnvironment) var environment

        guard let account = selectedAccount else {
            throw OfframpClientError.configuration("Select a wallet account before using P2P payments.")
        }
        guard account.vendor == .zcash else { throw OfframpClientError.unsupportedAccount }
        guard let fingerprint = account.seedFingerprint, !fingerprint.isEmpty else {
            throw OfframpClientError.configuration("The active wallet identity is unavailable. Reopen the wallet before using P2P payments.")
        }
        let accountID = account.id.id.map { String(format: "%02x", $0) }.joined()
        let seedFingerprint = fingerprint.map { String(format: "%02x", $0) }.joined()
        let network = environment.network().networkType == .testnet ? "testnet" : "mainnet"
        return "\(accountID):\(seedFingerprint):\(network)"
    }

    func previewTopUp(usdcMicros: String) async throws -> OfframpBridgePreview {
        let startedIn = try generationToken()
        let rail = try await offrampRail()
        try validateGeneration(startedIn)
        guard let amount = Decimal(string: usdcMicros), amount > 0, amount <= 100_000_000 else {
            throw OfframpClientError.configuration("Base top-ups are limited to 100 USDC.")
        }
        if try await rail.client.hasTopUpCheckpoint().boolValue {
            try validateGeneration(startedIn)
            guard try await rail.client.topUpCheckpointMicros() == usdcMicros else {
                throw OfframpClientError.configuration(
                    "A different Base top-up is already in progress. Resume or discard it first."
                )
            }
            return OfframpBridgePreview(
                sourceAmount: "Previously authorized",
                sourceAsset: "ZEC bridge",
                destinationAmount: OfframpSession.usdcDisplay(usdcMicros),
                destinationAsset: "USDC on Base",
                networkFee: nil,
                estimatedSeconds: 0
            )
        }
        guard let bridge = rail.bridge else {
            throw OfframpClientError.configuration("Automatic ZEC bridging is unavailable on this network.")
        }
        let preview = try await bridge.previewTopUp(
            accountAddress: try await rail.client.accountAddress(),
            usdcMicros: usdcMicros
        )
        try validateGeneration(startedIn)
        return preview
    }

    func previewRefund() async throws -> OfframpBridgePreview {
        let startedIn = try generationToken()
        let rail = try await offrampRail()
        try validateGeneration(startedIn)
        guard let bridge = rail.bridge else {
            throw OfframpClientError.configuration("Automatic Base refunds are unavailable on this network.")
        }
        try await prepareBaseReservations()
        try validateGeneration(startedIn)
        if let pendingMicros = try await rail.client.pendingRefundCommitmentMicros() {
            try validateGeneration(startedIn)
            return OfframpBridgePreview(
                sourceAmount: "Previously authorized",
                sourceAsset: "Base refund",
                destinationAmount: OfframpSession.usdcDisplay(pendingMicros),
                destinationAsset: "ZEC",
                networkFee: nil,
                estimatedSeconds: 0
            )
        }
        let account = try await rail.client.accountSummary()
        try validateGeneration(startedIn)
        guard let micros = account.balanceMicros,
              let rawBalance = UsdcAmount(micros: micros),
              rawBalance.isPositive else {
            throw OfframpClientError.configuration("The Base USDC balance could not be verified for refund.")
        }
        let spendable = await baseUSDCReservations.spendable(rawBalance: rawBalance)
        guard case .ready(_, committed: .zero) = spendable else {
            if case .ready = spendable {
                throw OfframpClientError.configuration(String(localizable: .p2pActivityRefundBlockedByPeer))
            }
            throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
        }
        let preview = try await bridge.previewRefund(
            accountAddress: account.address,
            usdcMicros: micros
        )
        try validateGeneration(startedIn)
        return preview
    }

    private static func usdcDisplay(_ micros: String) -> String {
        guard let value = Decimal(string: micros) else { return micros }
        return NSDecimalNumber(decimal: value / 1_000_000).stringValue
    }
}
