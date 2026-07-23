import XCTest
@testable import zodl_internal

final class MessagingLifecycleOwnerTests: XCTestCase {
    private actor Recorder {
        var values: [MessagingLifecycleOwner.State] = []
        func append(_ value: MessagingLifecycleOwner.State) { values.append(value) }
        func snapshot() -> [MessagingLifecycleOwner.State] { values }
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        _ predicate: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await predicate()
    }

    func testBackgroundRequestedDuringStartupIsAppliedAfterInstall() async {
        let owner = MessagingLifecycleOwner(flushTimeout: .seconds(1))
        let recorder = Recorder()

        await owner.setApplicationState(.background)
        await owner.install(
            suspend: { await recorder.append(.background) },
            resume: { await recorder.append(.foreground) }
        )

        let didSuspend = await eventually { await recorder.snapshot() == [.background] }
        XCTAssertTrue(didSuspend)
    }

    func testRapidTransitionsConvergeOnLatestForegroundState() async {
        let owner = MessagingLifecycleOwner(flushTimeout: .seconds(1))
        let recorder = Recorder()
        await owner.install(
            suspend: { await recorder.append(.background) },
            resume: { await recorder.append(.foreground) }
        )

        await owner.setApplicationState(.background)
        await owner.setApplicationState(.foreground)
        await owner.setApplicationState(.background)
        await owner.setApplicationState(.foreground)

        let didConverge = await eventually {
            let snapshot = await owner.snapshot()
            return snapshot.requested == .foreground && snapshot.applied == .foreground
        }
        XCTAssertTrue(didConverge)
        let finalAction = await recorder.snapshot().last
        XCTAssertNotEqual(finalAction, .background)
    }

    func testLateOlderRequestCannotOverrideLatestState() async {
        let owner = MessagingLifecycleOwner(flushTimeout: .seconds(1))
        let recorder = Recorder()
        await owner.install(
            suspend: { await recorder.append(.background) },
            resume: { await recorder.append(.foreground) }
        )

        await owner.setApplicationState(.foreground, sequence: 2)
        await owner.setApplicationState(.background, sequence: 1)

        let snapshot = await owner.snapshot()
        XCTAssertEqual(snapshot.requested, .foreground)
        XCTAssertEqual(snapshot.applied, .foreground)
        let actions = await recorder.snapshot()
        XCTAssertTrue(actions.isEmpty)
    }

    func testBackgroundWaitsForAcceptedSendThenSuspends() async {
        let owner = MessagingLifecycleOwner(flushTimeout: .seconds(1))
        let recorder = Recorder()
        await owner.install(
            suspend: { await recorder.append(.background) },
            resume: { await recorder.append(.foreground) }
        )
        let send = await owner.beginSend()

        await owner.setApplicationState(.background)
        try? await Task.sleep(for: .milliseconds(100))
        let actionsWhilePending = await recorder.snapshot()
        XCTAssertTrue(actionsWhilePending.isEmpty)

        await owner.finishSend(send)
        let didSuspend = await eventually { await recorder.snapshot() == [.background] }
        XCTAssertTrue(didSuspend)
    }

    func testExpirationSuspendsWithPendingSendAndRepeatedCallsAreIdempotent() async {
        let owner = MessagingLifecycleOwner(flushTimeout: .seconds(10))
        let recorder = Recorder()
        await owner.install(
            suspend: { await recorder.append(.background) },
            resume: { await recorder.append(.foreground) }
        )
        _ = await owner.beginSend()

        await owner.setApplicationState(.background)
        await owner.setApplicationState(.background)
        await owner.backgroundTimeExpired()

        let didSuspend = await eventually { await recorder.snapshot() == [.background] }
        XCTAssertTrue(didSuspend)
    }
}
