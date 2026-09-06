// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension DependencyValues {
    var giftProvingParams: GiftProvingParamsClient {
        get { self[GiftProvingParamsClient.self] }
        set { self[GiftProvingParamsClient.self] = newValue }
    }
}

/// Prefetches the Sapling proving parameters into the main wallet's parameter paths.
///
/// Required, not best-practice: the Swift encoder only *checks* for the files and throws when
/// absent, and the sync pipeline's own downloader runs only for a wallet holding sapling or
/// transparent balance — a gift wallet holds an ironwood note, so nothing ever downloads for it.
/// Without this, a fresh recipient reaches the spend with no params and the claim dies after the
/// scan already found their money.
@DependencyClient
struct GiftProvingParamsClient {
    /// Fire-and-forget, app-scoped, serialized, best-effort with retries. Callers never wait on
    /// it; a claim that reaches the spend without params fails as `paramsUnavailable` and retries
    /// after this succeeds.
    var prefetch: @Sendable () async -> Void
}

extension GiftProvingParamsClient: DependencyKey {
    static let liveValue = GiftProvingParamsClient.live()

    static func live() -> Self {
        let runner = GiftParamsPrefetchRunner()
        return Self(
            prefetch: { await runner.prefetch() }
        )
    }
}

/// Serializes concurrent prefetch triggers into one download at a time.
private actor GiftParamsPrefetchRunner {
    private var isRunning = false

    func prefetch() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        @Dependency(\.databaseFiles) var databaseFiles
        @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

        let network = zcashSDKEnvironment.network()
        // SHA-1-verified by the downloader; writes to the main wallet's param paths — a shared
        // good regardless, since the sender's first spend needs them too.
        _ = try? await SaplingParameterDownloader.downloadParamsIfnotPresent(
            retryEnabled: true,
            spendURL: databaseFiles.spendParamsURLFor(network),
            spendSourceURL: ZcashSDK.spendParamFileURL,
            outputURL: databaseFiles.outputParamsURLFor(network),
            outputSourceURL: ZcashSDK.outputParamFileURL,
            logger: OSLogger(logLevel: .error, category: "GiftParams")
        )
    }
}
