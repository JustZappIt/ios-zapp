// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct PeerCashOutProgressView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @Perception.Bindable var store: StoreOf<PeerCashOutProgress>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: store.title, subtitle: store.subtitle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !store.summaryRows.isEmpty {
                            ZappCompactLedger(rows: store.summaryRows)
                        }

                        ZappOfframpStepList(items: store.steps)

                        if let failure = store.failure {
                            failureCard(failure)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                    if store.depositID != nil {
                        ZappButton(title: String(localizable: .peerProgressViewOrder)) {
                            store.send(.viewOrderTapped)
                        }
                    }
                }
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
        }
    }

    private func failureCard(_ failure: PeerFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.message)
                .zappFont(.body, style: ZappColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            // What the user can be pointed at when the app cannot tell whether money moved. Never
            // a retry: the codes that reach here forbid one, and a second send opens a second
            // escrow.
            if let address = failure.depositorAddress {
                Text(String(localizable: .peerFailureInspectDepositor(address)))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }

            if let url = store.transactionURL {
                ZappButton(title: String(localizable: .peerFailureViewTransaction), variant: .ghost) {
                    openURL(url)
                }
            }

            if store.offersRetry {
                ZappButton(title: String(localizable: .peerProgressRetry)) { store.send(.retryTapped) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.dangerSoft.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.danger.color(colorScheme), lineWidth: 1))
    }
}

#Preview {
    PeerCashOutProgressView(
        store: Store(
            initialState: PeerCashOutProgress.State(attemptID: "0123456789abcdef0123456789abcdef")
        ) { PeerCashOutProgress() }
    )
    .applyScreenBackground()
}
