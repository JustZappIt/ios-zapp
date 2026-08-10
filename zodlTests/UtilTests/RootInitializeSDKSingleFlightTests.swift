//
//  RootInitializeSDKSingleFlightTests.swift
//  zodlTests
//
//  Regression tests for [#1943]: wallet initialization must be single-flight.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// `Root.State` embeds feature states that are not `Equatable`, while `TestStore` requires an
// equality witness. Keep every Root integration-test field in this single conformance; declaring
// another conformance in a sibling test file is a duplicate-conformance build error.
extension Root.State: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isInitializingSDK == rhs.isInitializingSDK
            && lhs.isRestoringWallet == rhs.isRestoringWallet
            && lhs.walletStatus == rhs.walletStatus
            && lhs.appInitializationState == rhs.appInitializationState
            && lhs.alert?.title == rhs.alert?.title
            && lhs.alert?.message == rhs.alert?.message
            && lhs.isStaleWalletHealedAlertPending == rhs.isStaleWalletHealedAlertPending
    }
}

// The launch chain logs through the process-global `LoggerProxy` and mutates TCA `@Shared`
// in-memory state, so this suite is serialized per repository convention.
@Suite(.serialized) @MainActor struct RootInitializeSDKSingleFlightTests {
    private final class PrepareGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                continuations.append(continuation)
                lock.unlock()
            }
        }

        func open() {
            lock.lock()
            let waiting = continuations
            continuations = []
            lock.unlock()
            waiting.forEach { $0.resume() }
        }
    }

    private static let seedDerivedAccount = WalletAccount(
        Account(
            id: AccountUUID(id: [UInt8](repeating: 0x01, count: 16)),
            name: "Zashi",
            keySource: "zashi",
            seedFingerprint: [UInt8](repeating: 0x02, count: 32),
            hdAccountIndex: Zip32AccountIndex(0),
            ufvk: nil,
            uivk: nil
        )
    )

    private func makeStore(
        prepareModes: LockIsolated<[String]>,
        messagingResumeCount: LockIsolated<Int>,
        gate: PrepareGate
    ) -> TestStore<Root.State, Root.Action> {
        let seedDerivedAccount = Self.seedDerivedAccount
        let initialState = Root.State(
            destinationState: Root.DestinationState(internalDestination: .welcome),
            exportLogsState: ExportLogs.State(),
            onboardingState: RestoreWalletCoordFlow.State(),
            phraseDisplayState: RecoveryPhraseDisplay.State(),
            walletConfig: .initial,
            welcomeState: Welcome.State()
        )

        let store = TestStore(initialState: initialState) {
            Root()
        } withDependencies: {
            $0.defaultInMemoryStorage = InMemoryStorage()
            $0.mainQueue = .immediate
            $0.exchangeRate = .noOp
            $0.autolockHandler = .noOp
            $0.shieldingProcessor = ShieldingProcessorClient(
                observe: { Empty().eraseToAnyPublisher() },
                shieldFunds: { }
            )
            $0.mnemonic = .noOp
            $0.diskSpaceChecker.hasEnoughFreeSpaceForSync = { true }
            $0.databaseFiles = .noOp
            $0.databaseFiles.areDbFilesPresentFor = { _ in true }
            $0.walletStorage = .noOp
            $0.walletStorage.areKeysPresent = { true }
            $0.walletStorage.exportWallet = { .placeholder }
            $0.userDefaults.objectForKey = { key in
                key == Root.Constants.udIsRestoringWallet ? true : nil
            }
            $0.userDefaults.setValue = { _, _ in }
            $0.userDefaults.remove = { _ in }
            $0.readTransactionsStorage = .noOp
            $0.addressBook.allLocalContacts = { _ in (AddressBookContacts.empty, .notAttempted) }
            $0.userMetadataProvider.load = { _ in }
            $0.zappMessaging.resume = {
                messagingResumeCount.withValue { $0 += 1 }
            }
            $0.sdkSynchronizer = .mocked(
                stateStream: { Empty().eraseToAnyPublisher() },
                prepareWith: { _, _, walletMode, _, _ in
                    let modeLabel: String
                    switch walletMode {
                    case .newWallet: modeLabel = "newWallet"
                    case .restoreWallet: modeLabel = "restoreWallet"
                    case .existingWallet: modeLabel = "existingWallet"
                    }
                    prepareModes.withValue { $0.append(modeLabel) }
                    await gate.wait()
                    return .success
                },
                getAllTransactions: { _ in [] },
                isSeedRelevantToAnyDerivedAccount: { _ in true },
                walletAccounts: { [seedDerivedAccount] }
            )
        }
        store.exhaustivity = .off
        return store
    }

    private func waitUntil(iterations: Int = 200, _ condition: @escaping @Sendable () -> Bool) async {
        for _ in 0..<iterations where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func drain(_ store: TestStore<Root.State, Root.Action>) async {
        await store.send(.cancelAllRunningEffects)
        await store.skipReceivedActions(strict: false)
        await store.skipInFlightEffects(strict: false)
    }

    @Test func foregroundWhileUnpreparedDoesNotDispatchSecondPrepare() async {
        let prepareModes = LockIsolated<[String]>([])
        let messagingResumeCount = LockIsolated(0)
        let gate = PrepareGate()
        let store = makeStore(
            prepareModes: prepareModes,
            messagingResumeCount: messagingResumeCount,
            gate: gate
        )

        await store.send(.initialization(.appDelegate(.didFinishLaunching)))
        await waitUntil { prepareModes.value.count >= 1 }
        #expect(prepareModes.value == ["restoreWallet"])

        // The synchronizer remains unprepared while the first call waits on the gate, so this
        // foreground event re-enters the initialization chain. Wallet preparation is dropped,
        // while Zapp's independent messaging lifecycle still resumes immediately.
        await store.send(.initialization(.appDelegate(.willEnterForeground)))
        await waitUntil(iterations: 50) { prepareModes.value.count >= 2 }

        #expect(prepareModes.value == ["restoreWallet"])
        #expect(messagingResumeCount.value == 1)

        gate.open()
        await drain(store)
    }
}
