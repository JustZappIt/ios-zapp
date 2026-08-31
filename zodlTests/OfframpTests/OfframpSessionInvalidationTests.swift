// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Testing
@testable import zodl_internal

struct OfframpSessionInvalidationTests {
    /// Cancellation is advisory across the Swift/Kotlin boundary. Invalidation owns and joins the
    /// task, so it cannot return while an old wallet's checkpoint write could still finish.
    @Test func invalidationJoinsCancellationResistantStateWritingWork() async {
        let session = OfframpSession()
        let release = SessionContinuationGate()
        let started = AsyncStream<Void>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        var startedIterator = started.stream.makeAsyncIterator()
        var cancelledIterator = cancelled.stream.makeAsyncIterator()

        let operation = Task {
            try? await session.runStateWritingOperationForTesting {
                started.continuation.yield()
                started.continuation.finish()
                await withTaskCancellationHandler {
                    await release.wait()
                } onCancel: {
                    cancelled.continuation.yield()
                    cancelled.continuation.finish()
                }
            }
        }
        _ = await startedIterator.next()

        let invalidationReturned = LockIsolated(false)
        let invalidation = Task {
            await session.invalidate()
            invalidationReturned.setValue(true)
        }
        _ = await cancelledIterator.next()
        #expect(!invalidationReturned.value)

        await release.open()
        await invalidation.value
        await operation.value

        #expect(invalidationReturned.value)
    }
}

private actor SessionContinuationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
