// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// The broker parks one continuation per request and resumes it from `complete` or from the
/// requester's own cancellation — a caller that stops waiting must never leave a lane open, and a
/// lane that answers must never resume a caller twice.
@Suite struct KeystoneSigningBrokerTests {
    private static let account = AccountUUID(id: [UInt8](repeating: 0x07, count: 16))

    @Test func aRequestIsPublishedAndResolvedByItsCompletion() async throws {
        let broker = KeystoneSigningBroker()
        var events = broker.events().makeAsyncIterator()
        let signing = Task { try await broker.sign(accountUUID: Self.account, proposal: .testOnlyFakeProposal(totalFee: 0)) }

        let request = try #require(await requested(&events))
        #expect(request.accountUUID == Self.account)

        let signed = KeystoneSignedPczt(pcztWithProofs: Data([0x01]), pcztWithSigs: Data([0x02]))
        await broker.complete(request.id, .success(signed))

        #expect(try await signing.value == signed)
    }

    @Test func aFailedCompletionThrowsItsReason() async throws {
        let broker = KeystoneSigningBroker()
        var events = broker.events().makeAsyncIterator()
        let signing = Task { try await broker.sign(accountUUID: Self.account, proposal: .testOnlyFakeProposal(totalFee: 0)) }

        let request = try #require(await requested(&events))
        await broker.complete(request.id, .failure(.rejected))

        await #expect(throws: KeystoneSigningError.rejected) { try await signing.value }
    }

    @Test func cancellingTheRequesterWithdrawsTheRequest() async throws {
        let broker = KeystoneSigningBroker()
        var events = broker.events().makeAsyncIterator()
        let signing = Task { try await broker.sign(accountUUID: Self.account, proposal: .testOnlyFakeProposal(totalFee: 0)) }
        let request = try #require(await requested(&events))

        signing.cancel()

        #expect(await events.next() == .withdrawn(request.id))
        await #expect(throws: CancellationError.self) { try await signing.value }
        // Answering a withdrawn request is a no-op, not a second resume.
        await broker.complete(request.id, .success(KeystoneSignedPczt(pcztWithProofs: Data(), pcztWithSigs: Data())))
    }

    @Test func aSubscriberAttachingLateIsReplayedThePendingRequest() async throws {
        let broker = KeystoneSigningBroker()
        var first = broker.events().makeAsyncIterator()
        let signing = Task { try await broker.sign(accountUUID: Self.account, proposal: .testOnlyFakeProposal(totalFee: 0)) }
        let request = try #require(await requested(&first))

        var second = broker.events().makeAsyncIterator()

        #expect(await second.next() == .requested(request))
        await broker.complete(request.id, .failure(.rejected))
        _ = try? await signing.value
    }

    @Test func completingAnUnknownRequestIsIgnored() async {
        let broker = KeystoneSigningBroker()
        await broker.complete(UUID(), .failure(.failed))
    }

    private func requested(_ events: inout AsyncStream<KeystoneSigningEvent>.Iterator) async -> KeystoneSigningRequest? {
        guard case .requested(let request) = await events.next() else { return nil }
        return request
    }
}
