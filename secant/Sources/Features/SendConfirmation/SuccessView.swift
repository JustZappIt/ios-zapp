//
//  SuccessView.swift
//  Zashi
//
//  Created by Lukáš Korba on 10-28-2024.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct SuccessView: View {
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

                store.successIlustration
                    .resizable()
                    .frame(width: Constants.illustrationSize, height: Constants.illustrationSize)

                Text(store.isShielding ? String(localizable: .sendSuccessShielding) : String(localizable: .sendSuccess))
                    .zappFont(.display, style: ZappColors.text)
                    .padding(.top, Design.Spacing._xl)

                Text(store.successInfo)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._md)

                if !store.isShielding && store.type == .regular {
                    Text(store.address.zip316)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .padding(.top, Design.Spacing._xs)
                }

                if store.txIdToExpand != nil || store.type == .regular {
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
                .padding(.bottom, store.type != .regular ? Design.Spacing._lg : Design.Spacing._3xl)

                if store.type != .regular {
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
}

#Preview {
    NavigationView {
        SuccessView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}
