// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension KeystoneSigningClient {
    /// `events` keeps its `.finished` default, so `Root`'s observer starts quietly; `sign` and
    /// `complete` stay unimplemented and fail any test that reaches them without an override.
    static let testValue = Self()

    static let noOp = Self(
        sign: { _, _ in KeystoneSignedPczt(pcztWithProofs: Pczt(), pcztWithSigs: Pczt()) },
        events: { .finished },
        complete: { _, _ in }
    )
}
