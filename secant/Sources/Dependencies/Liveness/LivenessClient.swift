// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

extension DependencyValues {
    var liveness: LivenessClient {
        get { self[LivenessClient.self] }
        set { self[LivenessClient.self] = newValue }
    }
}

typealias LivenessStatusStream = AsyncThrowingStream<LivenessStatusModel, Error>

/// Hosted selfie and passport checks. The shared driver validates durable authorization and
/// submits the signed attestation to the ReputationManager from the smart account.
@DependencyClient
struct LivenessClient {
    var verifyIdentity: @Sendable (_ check: IdentityCheckModel, _ currencyCode: String, _ nonce: String, _ runID: UUID)
        async throws -> LivenessStatusStream
    var cancel: @Sendable (_ check: IdentityCheckModel, _ currencyCode: String, _ runID: UUID) async throws -> Void = { _, _, _ in }
    var recoverable: @Sendable (_ currencyCode: String) async throws -> IdentityCheckModel? = { _ in nil }
    var verify: @Sendable (_ currencyCode: String, _ nonce: String, _ runID: UUID) async throws -> LivenessStatusStream
    var resume: @Sendable (_ ret: LivenessReturnModel, _ runID: UUID) async throws -> LivenessStatusStream
    /// Hands the widget's redirect to the live run. False when none is waiting: resume it instead.
    var deliverReturn: @Sendable (_ ret: LivenessReturnModel) async throws -> Bool
}

extension LivenessClient: DependencyKey {
    static let liveValue = Self.live()
    // Recovery reads may run on every appearance. Tests stay offline unless a closure is overridden;
    // the macro's write-operation defaults still report an unexpected call.
    static let testValue = Self()

    static func live() -> Self {
        Self(
            verifyIdentity: { check, currencyCode, nonce, runID in
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.verifyLiveness(
                    currencyCode: currencyCode, nonce: nonce, runID: runID, expectedGeneration: generation, check: check
                )
            },
            cancel: { check, currencyCode, runID in
                try await OfframpSession.shared.cancelIdentity(check: check, currencyCode: currencyCode, runID: runID)
            },
            recoverable: { currencyCode in
                try await OfframpSession.shared.recoverableIdentity(currencyCode: currencyCode)
            },
            verify: { currencyCode, nonce, runID in
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.verifyLiveness(
                    currencyCode: currencyCode,
                    nonce: nonce,
                    runID: runID,
                    expectedGeneration: generation
                )
            },
            resume: { ret, runID in
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.resumeLiveness(
                    ret,
                    runID: runID,
                    expectedGeneration: generation
                )
            },
            deliverReturn: { ret in
                try await OfframpSession.shared.deliverLivenessReturn(ret)
            }
        )
    }
}
