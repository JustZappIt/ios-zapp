// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension DependencyValues {
    var keystoneSigning: KeystoneSigningClient {
        get { self[KeystoneSigningClient.self] }
        set { self[KeystoneSigningClient.self] = newValue }
    }
}

/// A proposal a Zapp flow needs the Keystone device to sign. Answered by `Root`, which owns the
/// only screen that can show the animated QR and scan the signature back.
struct KeystoneSigningRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    /// The account the proposal was built for. The lane signs for the selected account, so a
    /// request for any other account is refused before a QR is shown.
    let accountUUID: AccountUUID
    let proposal: Proposal
}

/// What the lane hands back: the proved PCZT and the device-signed one, the pair
/// `createTransactionFromPCZT` combines. Neither has been broadcast, and neither has been stored
/// in the wallet database, so dropping them on the floor costs nothing.
struct KeystoneSignedPczt: Equatable, Sendable {
    let pcztWithProofs: Pczt
    let pcztWithSigs: Pczt
}

enum KeystoneSigningError: Error, Equatable {
    /// The sender backed out: Reject on the signing screen, or the lane was dismissed.
    case rejected
    /// The lane could not produce the pair — the PCZT could not be built or proved. The lane has
    /// already shown the details; the caller only needs to know nothing was sent.
    case failed
    /// The proposal belongs to an account other than the selected one, so the lane cannot sign it.
    case wrongAccount
    /// The lane is already showing another request.
    case busy
}

enum KeystoneSigningEvent: Equatable, Sendable {
    case requested(KeystoneSigningRequest)
    /// The requester stopped waiting — its task was cancelled — so the lane closes without an
    /// answer.
    case withdrawn(UUID)
}

/// The bridge between the code that must not know about screens (gift-card funding, the P2P
/// bridge worker) and the one screen that can talk to a Keystone. `sign` suspends the caller until
/// `Root` completes the request; `events` is `Root`'s side of the same exchange.
@DependencyClient
struct KeystoneSigningClient {
    /// Suspends until the device's signature for `proposal` is scanned, the sender rejects, or the
    /// lane fails. Throws `CancellationError` when the calling task is cancelled meanwhile, after
    /// telling the lane to close.
    var sign: @Sendable (AccountUUID, Proposal) async throws -> KeystoneSignedPczt
    var events: @Sendable () -> AsyncStream<KeystoneSigningEvent> = { .finished }
    var complete: @Sendable (UUID, Result<KeystoneSignedPczt, KeystoneSigningError>) async -> Void
}
