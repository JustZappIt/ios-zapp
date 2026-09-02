// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// One wallet-scoped authority for promises against the Base USDC balance.
///
/// The chain balance cannot represent a transaction that has been admitted locally but has not
/// landed yet. Every Base spender therefore claims here before broadcasting. Claims are serialized
/// on this actor, so two callers that both read the same balance cannot both spend it.
actor BaseUSDCReservationLedger {
    /// `CaseIterable` rather than a hand-written list: readiness is what makes every claim
    /// fail-closed, and a source added without being enumerated would fail open instead.
    enum Source: Hashable, Sendable, CaseIterable {
        case peer
        case scanAndPay
        case onrampDelivery
    }

    enum Owner: Hashable, Sendable {
        case peer(attemptID: String)
        /// Every newly-authorized payment gets a distinct owner. The durable recovery owner is
        /// deliberately separate, so two fresh payments for the same amount cannot be mistaken
        /// for an idempotent retry of one reservation.
        case scanAndPay(operationID: String)
        /// Refund is exclusive even when the currently visible balance is zero: it may first cancel
        /// an escrow and return that escrow's funds before moving the whole balance to ZEC.
        case refund(operationID: String)
        case onrampDelivery(operationID: String)
    }

    enum Settlement: Sendable {
        /// Durable evidence says no Base funds moved, or they have already returned to Base.
        case available
        /// An on-chain identity proves the debit landed. Keep the claim until a later balance read
        /// reflects it, otherwise an eventually-consistent RPC response can briefly count it twice.
        case spent
        /// The outcome is not known. Retain the claim until recovery supplies stronger evidence.
        case unknown
    }

    enum ClaimError: LocalizedError, Equatable {
        case recoveryUnavailable
        case insufficientAvailable(UsdcAmount)

        var errorDescription: String? {
            switch self {
            case .recoveryUnavailable:
                return String(localizable: .peerFormErrorBalanceUnavailable)
            case let .insufficientAvailable(available):
                return String(localizable: .peerFormErrorAboveAvailable(available.display))
            }
        }
    }

    private enum Readiness: Equatable, Sendable {
        case loading
        case ready
        case unavailable
    }

    private struct Reservation: Sendable {
        var amount: UsdcAmount
        var balanceAtClaim: UsdcAmount?
        var isConfirmedDebit = false
        let wasRestored: Bool
    }

    private var readiness = Dictionary(uniqueKeysWithValues: Source.allCases.map { ($0, Readiness.loading) })
    private var reservations: [Owner: Reservation] = [:]
    private var exclusiveOwner: Owner?

    /// Restores a durable, possibly-unspent promise without applying a current-balance admission
    /// check. Recovery records describe work that was already admitted by an earlier process.
    func restore(_ owner: Owner, amount: UsdcAmount) throws {
        guard amount.isPositive else { return }
        guard exclusiveOwner == nil || exclusiveOwner == owner else {
            throw ClaimError.recoveryUnavailable
        }
        if let existing = reservations[owner], existing.amount >= amount { return }
        reservations[owner] = Reservation(amount: amount, balanceAtClaim: nil, wasRestored: true)
    }

    /// Restores a refund that may first cancel an escrow and then sweep the resulting Base balance.
    /// Its checkpoint owns the whole account, not merely the amount visible before cancellation.
    func restoreExclusive(_ owner: Owner, amount: UsdcAmount) throws {
        guard amount.isPositive else { return }
        guard (exclusiveOwner == nil || exclusiveOwner == owner),
              reservations.isEmpty || (reservations.count == 1 && reservations[owner] != nil) else {
            // An unfinished refund owns the whole account. Finding any other recovered promise
            // beside it is an inconsistent recovery snapshot, never permission to sweep funds.
            throw ClaimError.recoveryUnavailable
        }
        try restore(owner, amount: amount)
        exclusiveOwner = owner
    }

    /// Resolves a durable p2p.me payment to the in-memory owner that admitted it, when this process
    /// is still alive, or installs a cold-start recovery owner. There can be only one p2p.me
    /// checkpoint; seeing two owners or a different amount is corrupted recovery state.
    func restoreOrFindScanAndPay(_ recoveryOwner: Owner, amount: UsdcAmount) throws -> Owner {
        let matches = reservations.filter { $0.key.isScanAndPay }
        if let match = matches.first {
            guard matches.count == 1, match.value.amount == amount else {
                throw ClaimError.recoveryUnavailable
            }
            return match.key
        }
        try restore(recoveryOwner, amount: amount)
        return recoveryOwner
    }

    /// Refund recovery is account-exclusive. Resolve a live owner without creating a second claim,
    /// or restore the cold-start owner only when no other promise can coexist with the sweep.
    func restoreOrFindRefund(_ recoveryOwner: Owner, amount: UsdcAmount) throws -> Owner {
        let matches = reservations.filter { $0.key.isRefund }
        if let match = matches.first {
            guard matches.count == 1,
                  reservations.count == 1,
                  exclusiveOwner == match.key else {
                throw ClaimError.recoveryUnavailable
            }
            // A refund can cancel an escrow before sweeping Base, so its durable amount may grow
            // from the balance visible at confirmation. The sole exclusive owner is still the same
            // operation; update its commitment instead of manufacturing a conflicting claim.
            var reservation = match.value
            reservation.amount = amount
            reservations[match.key] = reservation
            return match.key
        }
        try restoreExclusive(recoveryOwner, amount: amount)
        return recoveryOwner
    }

    func restoreOrFindOnrampDelivery(_ recoveryOwner: Owner, amount: UsdcAmount) throws -> Owner {
        let matches = reservations.filter { $0.key.isOnrampDelivery }
        if let match = matches.first {
            guard matches.count == 1, match.value.amount == amount else {
                throw ClaimError.recoveryUnavailable
            }
            return match.key
        }
        try restore(recoveryOwner, amount: amount)
        return recoveryOwner
    }

    /// The onramp checkpoint exists before the user authorizes its delivery. Move that recovered
    /// commitment to this explicit operation exactly once; a second fresh flow gets a new owner and
    /// is rejected instead of sharing idempotence with the first collector.
    func activateOnrampDelivery(_ owner: Owner, amount: UsdcAmount, rawBalance: UsdcAmount) throws {
        try requireReadableRecovery()
        calibrateRestoredClaims(rawBalance: rawBalance)
        retireObservedDebits(rawBalance: rawBalance)
        let matches = reservations.filter { $0.key.isOnrampDelivery }
        if matches.isEmpty {
            try claim(owner, amount: amount, rawBalance: rawBalance)
            return
        }
        guard matches.count == 1,
              let recovered = matches.first,
              recovered.value.wasRestored,
              recovered.value.amount == amount,
              committed <= rawBalance else {
            throw ClaimError.recoveryUnavailable
        }
        reservations[recovered.key] = nil
        reservations[owner] = Reservation(
            amount: recovered.value.amount,
            balanceAtClaim: recovered.value.balanceAtClaim,
            isConfirmedDebit: recovered.value.isConfirmedDebit,
            wasRestored: false
        )
    }

    func markLoading(_ source: Source) {
        readiness[source] = .loading
    }

    func markReady(_ source: Source) {
        readiness[source] = .ready
    }

    func markUnavailable(_ source: Source) {
        readiness[source] = .unavailable
    }

    /// Atomically admits one shared-balance spender against the raw on-chain balance.
    func claim(_ owner: Owner, amount: UsdcAmount, rawBalance: UsdcAmount) throws {
        try requireReadableRecovery()
        calibrateRestoredClaims(rawBalance: rawBalance)
        retireObservedDebits(rawBalance: rawBalance)
        guard exclusiveOwner == nil || exclusiveOwner == owner else {
            throw ClaimError.insufficientAvailable(.zero)
        }
        if var existing = reservations[owner] {
            guard existing.amount == amount else {
                throw ClaimError.insufficientAvailable(available(from: rawBalance))
            }
            if existing.balanceAtClaim == nil {
                existing.balanceAtClaim = rawBalance
                reservations[owner] = existing
            }
            return
        }
        let currentlyAvailable = available(from: rawBalance)
        guard amount.isPositive, amount <= currentlyAvailable else {
            throw ClaimError.insufficientAvailable(currentlyAvailable)
        }
        reservations[owner] = Reservation(amount: amount, balanceAtClaim: rawBalance, wasRestored: false)
    }

    /// Atomically claims the whole account. No shared spender may start until recovery proves this
    /// operation settled or moved nothing.
    func claimExclusive(_ owner: Owner, rawBalance: UsdcAmount) throws {
        try requireReadableRecovery()
        calibrateRestoredClaims(rawBalance: rawBalance)
        retireObservedDebits(rawBalance: rawBalance)
        if exclusiveOwner == owner { return }
        guard exclusiveOwner == nil, reservations.isEmpty else {
            throw ClaimError.insufficientAvailable(available(from: rawBalance))
        }
        exclusiveOwner = owner
        reservations[owner] = Reservation(amount: rawBalance, balanceAtClaim: rawBalance, wasRestored: false)
    }

    func settle(_ owner: Owner, as settlement: Settlement) {
        guard var reservation = reservations[owner] else { return }
        switch settlement {
        case .available:
            reservations[owner] = nil
            if exclusiveOwner == owner { exclusiveOwner = nil }
        case .spent:
            // A restored submission is resolved against an exact on-chain identity. It has no
            // trustworthy pre-send balance to compare against: even if a screen read calibrated
            // it first, that read may already include the debit. Requiring one more decrease would
            // subtract the recovered spend forever.
            if reservation.wasRestored {
                reservations[owner] = nil
                if exclusiveOwner == owner { exclusiveOwner = nil }
                return
            }
            reservation.isConfirmedDebit = true
            reservations[owner] = reservation
        case .unknown:
            break
        }
    }

    /// Returns a balance only when both recovery books were decoded successfully. Confirmed debits
    /// retire only after this fresh chain read reflects them.
    func spendable(rawBalance: UsdcAmount) -> PeerSpendableBalance {
        guard recoveryIsReadable else { return .unavailable }
        calibrateRestoredClaims(rawBalance: rawBalance)
        retireObservedDebits(rawBalance: rawBalance)
        guard exclusiveOwner == nil else { return .unavailable }
        return .ready(balance: rawBalance, committed: committed)
    }

    var committed: UsdcAmount {
        UsdcAmount.sum(reservations.values.map(\.amount))
    }

    func reset() {
        readiness = Dictionary(uniqueKeysWithValues: Source.allCases.map { ($0, Readiness.loading) })
        reservations.removeAll()
        exclusiveOwner = nil
    }

    private var recoveryIsReadable: Bool {
        Source.allCases.allSatisfy { readiness[$0] == .ready }
    }

    private func requireReadableRecovery() throws {
        guard recoveryIsReadable else { throw ClaimError.recoveryUnavailable }
    }

    private func available(from rawBalance: UsdcAmount) -> UsdcAmount {
        rawBalance.subtractingClampedToZero(committed)
    }

    private func retireObservedDebits(rawBalance: UsdcAmount) {
        let groups = Dictionary(grouping: reservations) { $0.value.balanceAtClaim?.microsString }
        for (baselineString, entries) in groups {
            guard let baselineString,
                  let baseline = UsdcAmount(micros: baselineString) else { continue }
            let confirmed = entries.filter { $0.value.isConfirmedDebit }
            guard !confirmed.isEmpty else { continue }
            let totalConfirmed = UsdcAmount.sum(confirmed.map { $0.value.amount })
            guard rawBalance <= baseline.subtractingClampedToZero(totalConfirmed) else { continue }

            for (owner, _) in confirmed {
                reservations[owner] = nil
                if exclusiveOwner == owner { exclusiveOwner = nil }
            }
            // Unconfirmed claims made from this exact snapshot must not consume the same observed
            // decrease later. Claims from a later, lower snapshot already have their own causal
            // baseline and are intentionally left alone.
            for (owner, var reservation) in entries where !reservation.isConfirmedDebit {
                if rawBalance < baseline {
                    reservation.balanceAtClaim = rawBalance
                    reservations[owner] = reservation
                }
            }
        }
    }

    private func calibrateRestoredClaims(rawBalance: UsdcAmount) {
        let restored = reservations.filter { $0.value.balanceAtClaim == nil }
        for (owner, var reservation) in restored {
            reservation.balanceAtClaim = rawBalance
            reservations[owner] = reservation
        }
    }
}

private extension BaseUSDCReservationLedger.Owner {
    var isScanAndPay: Bool {
        if case .scanAndPay = self { return true }
        return false
    }

    var isRefund: Bool {
        if case .refund = self { return true }
        return false
    }

    var isOnrampDelivery: Bool {
        if case .onrampDelivery = self { return true }
        return false
    }
}
