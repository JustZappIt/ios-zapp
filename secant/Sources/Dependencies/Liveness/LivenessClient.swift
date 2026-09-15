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

/// The selfie check: a browser widget, a one-time code on its redirect, an attestation written
/// to Zapp's integrator from the smart account.
@DependencyClient
struct LivenessClient {
    var verify: @Sendable (_ currencyCode: String, _ nonce: String, _ runID: UUID) async throws -> LivenessStatusStream
    var resume: @Sendable (_ ret: LivenessReturnModel, _ runID: UUID) async throws -> LivenessStatusStream
    /// Hands the widget's redirect to the live run. False when none is waiting: resume it instead.
    var deliverReturn: @Sendable (_ ret: LivenessReturnModel) async throws -> Bool
}

extension LivenessClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        Self(
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
