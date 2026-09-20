// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension DependencyValues {
    /// One process-wide intake store: the deeplink handler puts invites in, the preview screen
    /// takes them out by token, and the raw link never enters navigation state.
    var pendingGroupInvites: PendingGroupInviteStore {
        get { self[PendingGroupInviteStoreKey.self] }
        set { self[PendingGroupInviteStoreKey.self] = newValue }
    }
}

private enum PendingGroupInviteStoreKey: DependencyKey {
    static let liveValue = PendingGroupInviteStore(persistence: .keychain())
    /// Tests get memory, so one test's invite never reaches the next one or the device Keychain.
    static var testValue: PendingGroupInviteStore { PendingGroupInviteStore(persistence: .inMemory()) }
}
