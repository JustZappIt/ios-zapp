// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct PeerCashOutView: View {
    @Perception.Bindable var store: StoreOf<PeerCashOut>

    var body: some View {
        WithPerceptionTracking {
            switch store.page {
            case .form:
                PeerCashOutFormView(store: store.scope(state: \.form, action: \.form))
            case .progress:
                if let progress = store.scope(state: \.progress, action: \.progress) {
                    PeerCashOutProgressView(store: progress)
                }
            case .order:
                if let order = store.scope(state: \.order, action: \.order) {
                    PeerOrderView(store: order)
                }
            }
        }
    }
}

#Preview {
    PeerCashOutView(
        store: Store(initialState: PeerCashOut.State(destinationCode: "revolut")) { PeerCashOut() }
    )
    .applyScreenBackground()
}
