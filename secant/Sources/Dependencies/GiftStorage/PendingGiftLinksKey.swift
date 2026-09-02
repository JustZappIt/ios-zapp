// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension DependencyValues {
    /// One process-wide intake store: the deeplink handler puts links in, the claim screen takes
    /// them out by token, and the raw link never enters navigation state.
    var pendingGiftLinks: PendingGiftLinkStore {
        get { self[PendingGiftLinkStoreKey.self] }
        set { self[PendingGiftLinkStoreKey.self] = newValue }
    }
}

private enum PendingGiftLinkStoreKey: DependencyKey {
    static let liveValue = PendingGiftLinkStore()
    static let testValue = PendingGiftLinkStore()
}
