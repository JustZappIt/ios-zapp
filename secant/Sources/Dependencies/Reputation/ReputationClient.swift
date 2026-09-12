// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

extension DependencyValues {
    var reputation: ReputationClient {
        get { self[ReputationClient.self] }
        set { self[ReputationClient.self] = newValue }
    }
}

typealias ReclaimStatusStream = AsyncThrowingStream<ReclaimStatusModel, Error>

/// A build with no Reclaim credentials is deliberately not gated here: the driver reports
/// `NotConfigured` and the row says so, which is what Android does. Nothing asks in advance.
@DependencyClient
struct ReputationClient {
    var summary: @Sendable (_ currencyCode: String) async throws -> ReputationSummaryModel
    var verify: @Sendable (_ platformID: String, _ currencyCode: String, _ runID: UUID) async throws -> ReclaimStatusStream
    var resume: @Sendable (
        _ platformID: String,
        _ currencyCode: String,
        _ sessionID: String,
        _ runID: UUID
    ) async throws -> ReclaimStatusStream
    var markVerifierOpened: @Sendable (_ runID: UUID) async -> Void
}

extension ReputationClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        Self(
            summary: { currencyCode in
                ReputationSummaryModel(
                    try await OfframpSession.shared.reputationClient().summary(currencyCode: currencyCode)
                )
            },
            verify: { platformID, currencyCode, runID in
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.verifyReclaimPlatform(
                    platformID: platformID,
                    currencyCode: currencyCode,
                    runID: runID,
                    expectedGeneration: generation
                )
            },
            resume: { platformID, currencyCode, sessionID, runID in
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.resumeReclaimVerification(
                    platformID: platformID,
                    currencyCode: currencyCode,
                    sessionID: sessionID,
                    runID: runID,
                    expectedGeneration: generation
                )
            },
            markVerifierOpened: { runID in
                await OfframpSession.shared.markReclaimVerifierOpened(runID: runID)
            }
        )
    }
}

extension ReputationSummaryModel {
    init(_ value: AppleReputationSummary) {
        self.init(
            currencyCode: value.currencyCode,
            points: value.points,
            isBlocked: value.isBlacklisted,
            canBuy: value.canBuy,
            isAtCeiling: value.isAtCeiling,
            buyLimitMicros: value.buyLimitMicros,
            maxBuyLimitMicros: value.maxBuyLimitMicros,
            platforms: value.platforms.map(ReputationPlatformModel.init)
        )
    }
}

private extension ReputationPlatformModel {
    init(_ value: AppleReputationPlatform) {
        self.init(
            id: value.id,
            name: value.name,
            awardPoints: value.awardPoints,
            isVerified: value.isVerified,
            requiresMatureAccount: value.requiresMatureAccount,
            limitGainMicros: value.limitGainMicros
        )
    }
}

extension ReclaimStatusModel {
    init(_ value: AppleReclaimStatus) {
        switch onEnum(of: value) {
        case .preparing:
            self = .preparing
        case let .ready(ready):
            self = .ready(requestURL: ready.requestUrl)
        case .verifying:
            self = .verifying
        case .submitting:
            self = .submitting
        case let .done(done):
            self = .done(ReputationSummaryModel(done.summary))
        case let .failed(failed):
            // An unmapped reason is a framework this build is older than, not a user problem.
            self = .failed(ReclaimFailureModel(rawValue: failed.reason) ?? .unknown)
        }
    }
}
