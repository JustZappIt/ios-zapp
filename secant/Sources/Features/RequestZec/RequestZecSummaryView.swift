//
//  RequestZecSummaryView.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-30-2024.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct RequestZecSummaryView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let qrSize: CGFloat = 216
        static let qrPadding: CGFloat = 24
    }

    @Perception.Bindable var store: StoreOf<RequestZec>

    let tokenName: String

    init(store: StoreOf<RequestZec>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .generalRequest),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(spacing: 0) {
                        PrivacyBadge(store.maxPrivacy ? .max : .low)

                        Group {
                            Text(store.requestedZec.decimalString())
                            + Text(" \(tokenName)")
                                .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                        }
                        .zappFont(.display, style: ZappColors.text)
                        .minimumScaleFactor(0.1)
                        .lineLimit(1)
                        .padding(.top, Design.Spacing._md)

                        qrPanel
                            .padding(.top, Design.Spacing._4xl)

                        ZappButton(
                            title: String(localizable: .generalClose),
                            variant: .ghost
                        ) {
                            store.send(.cancelRequestTapped)
                        }
                        .padding(.top, Design.Spacing._4xl)
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.top, Design.Spacing._2xl)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }

                shareView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .zashiBack(primaryAction: {
                ZappButton(
                    title: String(localizable: .requestZecSummaryShareQR),
                    isEnabled: store.encryptedOutputToBeShared == nil,
                    leadingIcon: Asset.Assets.Icons.share.image
                ) {
                    store.send(.shareQR)
                }
            })
            .enlargeQR(isPresented: $store.isQRCodeEnlarged) {
                qrEnlargedCode()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(48)
                    .background {
                        if store.storedEnlargedQR != nil {
                            Rectangle()
                                .fill(Color.white)
                                .padding(24)
                        }
                    }
            }
        }
    }

    // The QR keeps a white fill in both themes: a scanner has to read it.
    private var qrPanel: some View {
        qrCode()
            .frame(width: Constants.qrSize, height: Constants.qrSize)
            .onAppear {
                store.send(.generateQRCode(colorScheme == .dark ? true : false))
            }
            .padding(Constants.qrPadding)
            .background(ZappColors.bg.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .onTapGesture {
                store.send(.qrCodeTapped, animation: .easeInOut)
            }
    }
}

extension RequestZecSummaryView {
    @ViewBuilder func qrCode(_ qrText: String = "") -> some View {
        Group {
            if let storedImg = store.storedQR {
                Image(storedImg, scale: 1, label: Text(localizable: .qrCodeFor(qrText)))
                    .resizable()
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder func qrEnlargedCode(_ qrText: String = "") -> some View {
        Group {
            if let storedImg = store.storedEnlargedQR {
                Image(storedImg, scale: 1, label: Text(localizable: .qrCodeFor(qrText)))
                    .resizable()
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder func shareView() -> some View {
        if let encryptedOutput = store.encryptedOutputToBeShared,
           let cgImg = QRCodeGenerator.generateCode(
            from: encryptedOutput,
            maxPrivacy: store.maxPrivacy,
            vendor: .zashi,
            color: .black
           ) {
            UIShareDialogView(activityItems: [
                ShareableImage(
                    image: UIImage(cgImage: cgImg),
                    title: String(localizable: .requestZecSummaryShareTitle),
                    reason: String(localizable: .requestZecSummaryShareDesc)
                ), "\(String(localizable: .requestZecSummaryShareDesc)) \(String(localizable: .requestZecSummaryShareMsg))"
            ]) {
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
        RequestZecSummaryView(store: RequestZec.placeholder, tokenName: "ZEC")
    }
}
