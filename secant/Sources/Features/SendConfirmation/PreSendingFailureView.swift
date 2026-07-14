//
//  PreSendingFailureView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-02-04.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct PreSendingFailureView: View {
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

                Text(store.isShielding ? String(localizable: .sendFailureShieldingInfo) : String(localizable: .sendFailureInfo))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._md)

                Spacer()

                ZappButton(title: String(localizable: .generalClose)) {
                    store.send(.backFromPCZTFailureTapped)
                }
                .padding(.bottom, Design.Spacing._md)

                ZappButton(
                    title: String(localizable: .sendReport),
                    variant: .ghost
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

extension PreSendingFailureView {
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
        PreSendingFailureView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}
