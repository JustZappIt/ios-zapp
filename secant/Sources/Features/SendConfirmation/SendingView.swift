//
//  SendingView.swift
//  Zashi
//
//  Created by Lukáš Korba on 10-28-2024.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

import Lottie

struct SendingView: View {
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

                Text(store.isShielding ? String(localizable: .sendShielding) : String(localizable: .sendSending))
                    .zappFont(.display, style: ZappColors.text)
                    .padding(.top, Design.Spacing._xl)

                Text(store.sendingInfo)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .lineLimit(store.type != .regular ? 3 : 1)
                    .minimumScaleFactor(store.type != .regular ? 1.0 : 0.5)
                    .multilineTextAlignment(.center)

                if !store.isShielding && store.type == .regular {
                    Text(store.address.zip316)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .padding(.top, Design.Spacing._xs)
                }

                Spacer()
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.sendingScreenOnAppear) }
        }
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    NavigationView {
        SendingView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}
