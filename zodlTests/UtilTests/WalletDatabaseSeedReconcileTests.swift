import Testing
@testable import zodl_internal

@Suite struct WalletDatabaseSeedReconcileTests {
    @Test func relevantSeedSkipsHealAndReturnsFalse() async throws {
        let recorder = ReconcileCallRecorder()
        let healed = try await Root.reconcileWalletDatabaseWithSeed(
            knownStale: false,
            seedBytes: [1, 2, 3],
            isSeedRelevant: { _ in
                await recorder.record("isSeedRelevant")
                return true
            },
            hasSeedDerivedAccount: {
                await recorder.record("hasSeedDerivedAccount")
                return true
            },
            clearDeviceScopedState: { await recorder.record("clear") },
            wipe: { await recorder.record("wipe") },
            reprepare: { await recorder.record("reprepare") }
        )

        #expect(!healed)
        let calls = await recorder.calls
        #expect(calls == ["isSeedRelevant"])
    }

    @Test func irrelevantSeedWithDerivedAccountHealsInOrder() async throws {
        let recorder = ReconcileCallRecorder()
        let healed = try await Root.reconcileWalletDatabaseWithSeed(
            knownStale: false,
            seedBytes: [1, 2, 3],
            isSeedRelevant: { _ in
                await recorder.record("isSeedRelevant")
                return false
            },
            hasSeedDerivedAccount: {
                await recorder.record("hasSeedDerivedAccount")
                return true
            },
            clearDeviceScopedState: { await recorder.record("clear") },
            wipe: { await recorder.record("wipe") },
            reprepare: { await recorder.record("reprepare") }
        )

        #expect(healed)
        let calls = await recorder.calls
        #expect(calls == ["isSeedRelevant", "hasSeedDerivedAccount", "clear", "wipe", "reprepare"])
    }

    @Test func knownStaleSkipsProbesButStillHeals() async throws {
        let recorder = ReconcileCallRecorder()
        let healed = try await Root.reconcileWalletDatabaseWithSeed(
            knownStale: true,
            seedBytes: [1, 2, 3],
            isSeedRelevant: { _ in
                await recorder.record("isSeedRelevant")
                return true
            },
            hasSeedDerivedAccount: {
                await recorder.record("hasSeedDerivedAccount")
                return false
            },
            clearDeviceScopedState: { await recorder.record("clear") },
            wipe: { await recorder.record("wipe") },
            reprepare: { await recorder.record("reprepare") }
        )

        #expect(healed)
        let calls = await recorder.calls
        #expect(calls == ["clear", "wipe", "reprepare"])
    }

    @Test func relevanceFailureNeverHeals() async {
        let recorder = ReconcileCallRecorder()
        await #expect(throws: ReconcileTestError.boom) {
            try await Root.reconcileWalletDatabaseWithSeed(
                knownStale: false,
                seedBytes: [1, 2, 3],
                isSeedRelevant: { _ in throw ReconcileTestError.boom },
                hasSeedDerivedAccount: {
                    await recorder.record("hasSeedDerivedAccount")
                    return true
                },
                clearDeviceScopedState: { await recorder.record("clear") },
                wipe: { await recorder.record("wipe") },
                reprepare: { await recorder.record("reprepare") }
            )
        }
        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    @Test func viewOnlyDatabaseNeverHeals() async {
        let recorder = ReconcileCallRecorder()
        do {
            _ = try await Root.reconcileWalletDatabaseWithSeed(
                knownStale: false,
                seedBytes: [1, 2, 3],
                isSeedRelevant: { _ in false },
                hasSeedDerivedAccount: { false },
                clearDeviceScopedState: { await recorder.record("clear") },
                wipe: { await recorder.record("wipe") },
                reprepare: { await recorder.record("reprepare") }
            )
            Issue.record("Expected the view-only database guard to throw")
        } catch Root.WalletDatabaseHealError.viewOnlyDatabase {
            // Expected.
        } catch {
            Issue.record("Expected viewOnlyDatabase, got \(error)")
        }
        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    @Test func derivedAccountProbeFailureNeverHeals() async {
        let recorder = ReconcileCallRecorder()
        await #expect(throws: ReconcileTestError.boom) {
            try await Root.reconcileWalletDatabaseWithSeed(
                knownStale: false,
                seedBytes: [1, 2, 3],
                isSeedRelevant: { _ in false },
                hasSeedDerivedAccount: { throw ReconcileTestError.boom },
                clearDeviceScopedState: { await recorder.record("clear") },
                wipe: { await recorder.record("wipe") },
                reprepare: { await recorder.record("reprepare") }
            )
        }
        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    @Test func clearFailureNeverWipes() async {
        let recorder = ReconcileCallRecorder()
        await #expect(throws: ReconcileTestError.boom) {
            try await Root.reconcileWalletDatabaseWithSeed(
                knownStale: false,
                seedBytes: [1, 2, 3],
                isSeedRelevant: { _ in false },
                hasSeedDerivedAccount: { true },
                clearDeviceScopedState: { throw ReconcileTestError.boom },
                wipe: { await recorder.record("wipe") },
                reprepare: { await recorder.record("reprepare") }
            )
        }
        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    @Test func wipeFailureNeverReprepares() async {
        let recorder = ReconcileCallRecorder()
        await #expect(throws: ReconcileTestError.boom) {
            try await Root.reconcileWalletDatabaseWithSeed(
                knownStale: false,
                seedBytes: [1, 2, 3],
                isSeedRelevant: { _ in false },
                hasSeedDerivedAccount: { true },
                clearDeviceScopedState: { },
                wipe: { throw ReconcileTestError.boom },
                reprepare: { await recorder.record("reprepare") }
            )
        }
        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    @Test func reprepareFailureIsWrapped() async {
        do {
            _ = try await Root.reconcileWalletDatabaseWithSeed(
                knownStale: false,
                seedBytes: [1, 2, 3],
                isSeedRelevant: { _ in false },
                hasSeedDerivedAccount: { true },
                clearDeviceScopedState: { },
                wipe: { },
                reprepare: { throw ReconcileTestError.boom }
            )
            Issue.record("Expected reprepareFailed")
        } catch Root.WalletDatabaseHealError.reprepareFailed(let underlying) {
            #expect(underlying as? ReconcileTestError == .boom)
        } catch {
            Issue.record("Expected reprepareFailed, got \(error)")
        }
    }
}

private enum ReconcileTestError: Error, Equatable {
    case boom
}

private actor ReconcileCallRecorder {
    private(set) var calls: [String] = []

    func record(_ name: String) {
        calls.append(name)
    }
}
