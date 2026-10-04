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

                        addressSection
                            .padding(.top, Design.Spacing._3xl)

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

    /// Android's `RequestQrCodeView.AddressSection`: which address is being requested into, with a
    /// copy action, then the note the request carries (if any).
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                String(localizable: store.maxPrivacy ? .requestZecAddressShielded : .requestZecAddressTransparent)
                    .uppercased()
            )
            .zappFont(.groupLabel, style: ZappColors.textSubtle)
            .padding(.bottom, Design.Spacing._md)

            HStack(spacing: Design.Spacing._md) {
                Text(store.address.data.zappEllipsized())
                    .zappFont(.mono, style: ZappColors.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(store.address.data)

                Button {
                    store.send(.copyAddressTapped)
                } label: {
                    Asset.Assets.copy.image
                        .zImage(width: 18, height: 18, style: ZappColors.accentText)
                        .frame(width: 40, height: 40)
                        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .requestZecCopyAddress))
            }

            if !store.memoState.text.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                    Text(localizable: .requestZecNoteLabel)
                        .zappFont(.groupLabel, style: ZappColors.textSubtle)

                    Text(store.memoState.text)
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
                .padding(.top, Design.Spacing._lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
