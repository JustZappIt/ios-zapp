//
//  MessagingLifecycleOwner.swift
//  Zapp
//

import Foundation

/// Serializes the worklet's application-lifecycle state independently of the
/// wallet synchronizer. The reconciliation loop is latest-state-wins, including
/// foreground/background changes that arrive while startup or a transition is
/// still in flight.
actor MessagingLifecycleOwner {
    enum State: Equatable, Sendable {
        case foreground
        case background
    }

    typealias Transition = @Sendable () async -> Void

    private let flushTimeout: Duration
    private var requestedState: State = .foreground
    private var appliedState: State?
    private var suspendAction: Transition?
    private var resumeAction: Transition?
    private var pendingSends: Set<UUID> = []
    private var backgroundDeadline: ContinuousClock.Instant?
    private var reconciliationTask: Task<Void, Never>?
    private var latestRequestSequence: UInt64 = 0

    init(flushTimeout: Duration = .seconds(20)) {
        self.flushTimeout = flushTimeout
    }

    func install(
        initially: State = .foreground,
        suspend: @escaping Transition,
        resume: @escaping Transition
    ) {
        suspendAction = suspend
        resumeAction = resume
        appliedState = initially
        scheduleReconciliation()
    }

    func uninstall() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        suspendAction = nil
        resumeAction = nil
        appliedState = nil
        pendingSends.removeAll()
        backgroundDeadline = nil
    }

    func setApplicationState(_ state: State, sequence: UInt64? = nil) {
        let requestSequence = sequence ?? latestRequestSequence &+ 1
        guard requestSequence > latestRequestSequence else { return }
        latestRequestSequence = requestSequence
        requestedState = state
        backgroundDeadline = state == .background
            ? ContinuousClock.now.advanced(by: flushTimeout)
            : nil
        scheduleReconciliation()
    }

    func beginSend() -> UUID {
        let id = UUID()
        pendingSends.insert(id)
        return id
    }

    func finishSend(_ id: UUID) {
        pendingSends.remove(id)
        scheduleReconciliation()
    }

    /// Called by UIKit's expiration handler. The in-flight IPC call will remain
    /// pending/retryable, but networking must stop before iOS freezes the app.
    func backgroundTimeExpired() {
        backgroundDeadline = .now
        scheduleReconciliation()
    }

    func snapshot() -> (requested: State, applied: State?, pendingSends: Int) {
        (requestedState, appliedState, pendingSends.count)
    }

    private func scheduleReconciliation() {
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { [weak self] in
            await self?.reconcileUntilSettled()
        }
    }

    private func reconcileUntilSettled() async {
        defer {
            reconciliationTask = nil
            if appliedState != requestedState, suspendAction != nil {
                scheduleReconciliation()
            }
        }

        while !Task.isCancelled, let suspendAction, let resumeAction {
            let target = requestedState
            guard appliedState != target else { return }

            if target == .background, !pendingSends.isEmpty {
                if let deadline = backgroundDeadline, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                print("[ZappMessagingLifecycle] Background flush window expired with " +
                      "\(pendingSends.count) send(s) pending; suspending")
            }

            switch target {
            case .foreground:
                await resumeAction()
            case .background:
                await suspendAction()
            }
            appliedState = target
        }
    }
}
