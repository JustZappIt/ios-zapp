//
//  PendingView.swift
//  Zashi
//
//  Created by Lukáš Korba on 12-09-2025.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit
import Lottie

struct PendingView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let lottieNameLight = "sending"
        static let lottieNameDark = "sending-dark"
        static let lottieSize: CGFloat = 170
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

                LottieView(
                    animation: .named(
                        colorScheme == .light ? Constants.lottieNameLight : Constants.lottieNameDark
                    )
                )
                .resizable()
                .looping()
                .frame(width: Constants.lottieSize, height: Constants.lottieSize)

                Text(store.pendingTitle)
                    .zappFont(.display, style: ZappColors.text)
                    .padding(.top, Design.Spacing._xl)

                Text(store.pendingInfo)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._md)

                if store.txIdToExpand != nil {
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
                    variant: showsCheckStatus ? .ghost : .primary
                ) {
                    store.send(.closeTapped)
                }
                .padding(.bottom, showsCheckStatus ? Design.Spacing._lg : Design.Spacing._3xl)

                if showsCheckStatus {
                    ZappButton(title: String(localizable: .swapAndPayCheckStatus)) {
                        store.send(.checkStatusTapped)
                    }
                    .padding(.bottom, Design.Spacing._3xl)
                }
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
        }
        .navigationBarBackButtonHidden()
    }

    private var showsCheckStatus: Bool {
        store.type != .regular && store.txIdToExpand != nil
    }
}

#Preview {
    NavigationView {
        PendingView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}
