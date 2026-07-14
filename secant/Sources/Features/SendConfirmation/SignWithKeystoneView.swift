//
//  SignWithKeystoneView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2024-11-29.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

@preconcurrency import KeystoneSDK
import URKit

struct SignWithKeystoneView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) var presentationMode

    private enum Constants {
        static let vendorIconSize: CGFloat = 24
        static let vendorIconBox: CGFloat = 40
        static let qrSize: CGFloat = 216
        static let qrRenderSize: CGFloat = 250
        static let qrPadding: CGFloat = 24
    }

    @Perception.Bindable var store: StoreOf<SendConfirmation>

    @Dependency(\.sdkSynchronizer) var sdkSynchronizer

    let tokenName: String

    init(store: StoreOf<SendConfirmation>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .keystoneSignWithSignTransaction),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(spacing: 0) {
                        accountCard

                        qrPanel
                            .padding(.top, Design.Spacing._4xl)

                        Text(localizable: .keystoneSignWithTitle)
                            .zappFont(.sectionTitle, style: ZappColors.text)
                            .padding(.top, Design.Spacing._4xl)

                        Text(localizable: .keystoneSignWithDesc)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Design.Spacing._xs)
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.top, Design.Spacing._2xl)
                }

                #if DEBUG
                ZappButton(title: "Share PCZT", variant: .ghost) {
                    store.send(.sharePCZT)
                }
                .padding(.horizontal, Design.Spacing._2xl)
                #endif

                VStack(spacing: Design.Spacing._md) {
                    ZappButton(
                        title: String(localizable: .keystoneSignWithReject),
                        variant: .danger
                    ) {
                        store.send(.rejectRequested)
                    }

                    ZappButton(title: String(localizable: .keystoneSignWithGetSignature)) {
                        store.send(.getSignatureTapped)
                    }
                }
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.top, Design.Spacing._xl)
                .padding(.bottom, Design.Spacing._3xl)

                shareView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiSheet(isPresented: $store.rejectSendRequest) {
                rejectSendContent(colorScheme: colorScheme)
            }
            .onAppear { store.send(.onAppear) }
        }
        .navigationBarBackButtonHidden(true)
        .enlargeQR(isPresented: $store.isQRCodeEnlarged) {
            Group {
                if let pczt = store.pcztForUI, let encoder = sdkSynchronizer.urEncoderForPCZT(pczt) {
                    AnimatedQRCode(urEncoder: encoder, size: UIScreen.main.bounds.width - 64)
                        .padding()
                        .background(Color.white)
                }
            }
        }
    }

    private var accountCard: some View {
        HStack(spacing: Design.Spacing._lg) {
            Asset.Assets.Partners.keystoneLogo.image
                .resizable()
                .frame(width: Constants.vendorIconSize, height: Constants.vendorIconSize)
                .frame(width: Constants.vendorIconBox, height: Constants.vendorIconBox)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(localizable: .accountsKeystone)
                    .zappFont(.rowTitle, style: ZappColors.text)

                Text(store.selectedWalletAccount?.unifiedAddress?.zip316 ?? "")
                    .zappFont(.mono, style: ZappColors.textMuted)
            }

            Spacer(minLength: 0)

            ZappStatusChip(text: String(localizable: .keystoneSignWithHardware), variant: .muted)
        }
        .padding(Design.Spacing._lg)
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
    }

    // The QR panel keeps a white fill in both themes: a Keystone camera has to read it.
    @ViewBuilder private var qrPanel: some View {
        Group {
            if let pczt = store.pcztForUI, let encoder = sdkSynchronizer.urEncoderForPCZT(pczt), !store.isQRCodeEnlarged {
                AnimatedQRCode(urEncoder: encoder, size: Constants.qrRenderSize)
                    .frame(width: Constants.qrSize, height: Constants.qrSize)
            } else {
                ProgressView()
                    .frame(width: Constants.qrSize, height: Constants.qrSize)
            }
        }
        .padding(Constants.qrPadding)
        .background(Color.white)
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .onTapGesture {
            store.send(.enlargeQRCodeTapped, animation: .easeInOut)
        }
    }
}

extension SignWithKeystoneView {
    @ViewBuilder func shareView() -> some View {
        if let pczt = store.pcztToShare {
            UIShareDialogView(activityItems: [pczt]) {
                store.send(.shareFinished)
            }
            .frame(width: 0, height: 0)
        }
    }
}
