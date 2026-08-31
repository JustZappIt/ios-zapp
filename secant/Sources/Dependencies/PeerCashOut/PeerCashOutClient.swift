// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

enum PeerCashOutClientError: LocalizedError, Equatable {
    case unavailable
    case authenticationCancelled
    case unknownDestination(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localizable: .peerErrorUnavailable)
        case .authenticationCancelled:
            return String(localizable: .peerErrorAuthenticationCancelled)
        case .unknownDestination:
            return String(localizable: .peerErrorUnavailable)
        }
    }
}

extension DependencyValues {
    var peerCashOut: PeerCashOutClient {
        get { self[PeerCashOutClient.self] }
        set { self[PeerCashOutClient.self] = newValue }
    }
}

/// The Peer maker rails, as the reducers see them.
///
/// The split between the reads here and the work behind ``runnerState`` is the important one. A
/// read answers the screen that asked it; the running work belongs to the app-lifetime runner, so
/// dismissing a screen stops the watching and nothing else.
///
/// Every closure that can move USDC on Base authenticates immediately before it does — and the ones
/// that cannot, deliberately do not: a balance, quote, market or order refresh that prompted would
/// train the user to approve prompts without reading them.
@DependencyClient
struct PeerCashOutClient {
    /// Whether the rails exist for this build and this account, answered from local configuration
    /// alone. Routing reads this rather than ``capabilities`` so an outage cannot be mistaken for a
    /// product that is not there and quietly open a different one.
    var isConfigured: @Sendable () -> Bool = { false }

    /// Peer exists only on Base mainnet. Every surface is gated on this, so a build without the
    /// rails hides them rather than failing at the first call.
    var capabilities: @Sendable () async throws -> PeerCapabilities

    /// The Base balance less everything unfinished attempts have promised and not yet escrowed.
    var spendableBalance: @Sendable () async throws -> PeerSpendableBalance

    /// Pure and cheap: the amount screen echoes what a handle registers as on every keystroke.
    var normalizeHandle: @Sendable (_ destinationCode: String, _ raw: String) async throws -> PeerHandleCheck
    var storedHandle: @Sendable (_ destinationCode: String) async throws -> String?

    var rate: @Sendable (_ currencyCode: String) async throws -> PeerRate?
    var market: @Sendable (
        _ destinationCode: String,
        _ currencyCode: String,
        _ amount: UsdcAmount?
    ) async throws -> PeerMarketReading?

    var activeOrders: @Sendable () async throws -> [PeerOrder]
    var orderHistory: @Sendable () async throws -> [PeerOrder]
    var order: @Sendable (_ depositID: String) async throws -> PeerOrder?
    var observeOrder: @Sendable (_ depositID: String) async throws -> AsyncStream<PeerProgress>

    /// Authenticates, then hands the attempt to the runner and returns the id everything else hangs
    /// off: the checkpoint it will write, and the progress screen that watches it.
    var startCashOut: @Sendable (_ draft: PeerCashOutDraft) async throws -> String

    /// Resolves what a stored record says was already broadcast. Reads only, so it never prompts.
    var recoverCashOut: @Sendable (_ attemptID: String) async throws -> Void

    /// The explicit retry. May broadcast, so it authenticates.
    var retryCashOut: @Sendable (_ attemptID: String) async throws -> Void

    var withdraw: @Sendable (_ depositID: String, _ amount: UsdcAmount) async throws -> Void
    var setAcceptingIntents: @Sendable (_ depositID: String, _ accepting: Bool) async throws -> Void
    var clearOrderAction: @Sendable (_ depositID: String) async -> Void

    /// Everything the runner is carrying, republished on every change. Several screens observe at
    /// once and each gets its own stream.
    var runnerState: @Sendable () async throws -> AsyncStream<PeerRunnerState>

    var transactionURL: @Sendable (_ txHash: String) async throws -> URL?
}
