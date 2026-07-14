//
//  FailedView.swift
//  Zashi
//
//  Created by Lukáš Korba on 22.01.2026.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct FailureView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let illustrationSize: CGFloat = 148
    }

    @Perception.Bindable var store: StoreOf<SendConfirmation>
    let tokenName: String

    init(store: StoreOf<SendConfirmation>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                store.failureIlustration
                    .resizable()
                    .frame(width: Constants.illustrationSize, height: Constants.illustrationSize)

                Text(store.isShielding ? String(localizable: .sendFailureShielding) : String(localizable: .sendFailure))
                    .zappFont(.display, style: ZappColors.text)
                    .padding(.top, Design.Spacing._xl)

                Text(store.failureInfo)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._md)

                if store.txIdToExpand != nil || store.type != .regular {
                    ZappButton(
                        title: String(localizable: .sendViewTransaction),
                        variant: .accentGhost
                    ) {
                        store.send(.viewTransactionTapped)
                    }
                    .padding(.top, Design.Spacing._xl)
                }

                Spacer()

                ZappButton(
                    title: String(localizable: .generalClose),
                    variant: store.type != .regular ? .ghost : .primary
                ) {
                    store.send(.closeTapped)
                }
                .padding(.bottom, Design.Spacing._md)

                ZappButton(
                    title: String(localizable: .sendReport),
                    variant: store.type != .regular ? .primary : .ghost
                ) {
                    store.send(.reportTapped)
                }
                .padding(.bottom, Design.Spacing._3xl)

                if let supportData = store.supportData {
                    UIMailDialogView(
                        supportData: supportData,
                        completion: {
                            store.send(.sendSupportMailFinished)
                        }
                    )
                    // UIMailDialogView only wraps MFMailComposeViewController presentation
                    // so frame is set to 0 to not break SwiftUI's layout
                    .frame(width: 0, height: 0)
                }

                shareMessageView()
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
        }
        .navigationBarBackButtonHidden()
    }
}

extension FailureView {
    @ViewBuilder func shareMessageView() -> some View {
        if let message = store.messageToBeShared {
            UIShareDialogView(activityItems: [message]) {
                store.send(.shareFinished)
            }
            // UIShareDialogView only wraps UIActivityViewController presentation
            // so frame is set to 0 to not break SwiftUI's layout
            .frame(width: 0, height: 0)
        } else {
            EmptyView()
        }
    }
}

#Preview {
    NavigationView {
        FailureView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}
