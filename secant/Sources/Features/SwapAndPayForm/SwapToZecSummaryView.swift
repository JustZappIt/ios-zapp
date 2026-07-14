//
//  SwapToZecSummaryView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-09-12.
//

import SwiftUI
import ComposableArchitecture

struct SwapToZecSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let qrSize: CGFloat = 216
        static let qrPadding: CGFloat = 24
        static let tickerSize: CGFloat = 40
        static let tickerBadgeSize: CGFloat = 18
        static let actionMinHeight: CGFloat = 64
        static let actionIconSize: CGFloat = 20
        static let toolbarIconSize: CGFloat = 22
        static let toolbarTouchTarget: CGFloat = 44
    }

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false

    @Perception.Bindable var store: StoreOf<SwapAndPay>
    let tokenName: String

    init(store: StoreOf<SwapAndPay>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .swapAndPaySwap),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: {
                        Button {
                            store.send(.openDepositHelpSheetTapped)
                        } label: {
                            Asset.Assets.infoCircle.image
                                .zImage(
                                    width: Constants.toolbarIconSize,
                                    height: Constants.toolbarIconSize,
                                    style: ZappColors.text
                                )
                                .frame(width: Constants.toolbarTouchTarget, height: Constants.toolbarTouchTarget)
                        }
                        .buttonStyle(.zappPress)
                    }
                )

                ScrollView {
                    VStack(spacing: Design.Spacing._2xl) {
                        depositAmount

                        qrPanel

                        if let depositAddress = store.quote?.depositAddress {
                            Text(depositAddress.truncateMiddle10)
                                .zappFont(.mono, style: ZappColors.text)
                                .padding(.horizontal, Design.Spacing._lg)
                                .padding(.vertical, Design.Spacing._md)
                                .background(ZappColors.surfaceAlt.color(colorScheme))
                        }

                        HStack(spacing: Design.Spacing._md) {
                            actionButton(
                                title: String(localizable: .receiveCopy),
                                icon: Asset.Assets.copy.image
                            ) {
                                store.send(.copyDepositAddressToPastboard)
                            }

                            actionButton(
                                title: String(localizable: .swapToZecShareQR),
                                icon: Asset.Assets.Icons.qr.image
                            ) {
                                store.send(.shareQR)
                            }
                        }

                        Group {
                            Text(localizable: .swapToZecInfo1)
                            + Text(localizable: .swapToZecInfo2(store.selectedAsset?.token ?? "", store.selectedAsset?.chainName ?? "")).bold()
                            + Text(localizable: .swapToZecInfo3)
                        }
                        .zappFont(.body, style: ZappColors.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.top, Design.Spacing._xl)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }

                shareView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiSheet(isPresented: $store.isDepositHelpSheetVisible) {
                helpSheetContent(colorScheme)
            }
            .alert(
                store: store.scope(
                    state: \.$alert,
                    action: \.alert
                )
            )
            .zashiBack(
                primaryAction: {
                    ZappButton(title: String(localizable: .swapToZecSentTheFunds)) {
                        store.send(.sentTheFundsButtonTapped)
                    }
                },
                customDismiss: { store.send(.depositFundsBackTapped) }
            )
            .enlargeQR(isPresented: $store.isQRCodeEnlarged) {
                qrEnlargedCode(store.quote?.depositAddress ?? "")
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

    private var depositAmount: some View {
        Button {
            store.send(.copySwapToZecAmountTapped)
        } label: {
            VStack(spacing: Design.Spacing._md) {
                HStack(spacing: Design.Spacing._md) {
                    ZappSectionLabel(text: String(localizable: .swapToZecDeposit))

                    Asset.Assets.copy.image
                        .zImage(width: 16, height: 16, style: ZappColors.textMuted)
                }

                HStack(spacing: Design.Spacing._md) {
                    tokenTicker(asset: store.selectedAsset, colorScheme)

                    Text(store.swapToZecAmountInQuotePreciseCopy)
                        .zappFont(.display, style: ZappColors.text)
                        .minimumScaleFactor(0.1)
                        .lineLimit(1)
                }

                Text(store.zecUsdToBeSpendInQuote)
                    .zappFont(.rowTitle, style: ZappColors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    // The QR keeps a white fill in both themes: a sending wallet has to scan it.
    private var qrPanel: some View {
        qrCode(store.quote?.depositAddress ?? "")
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

    private func actionButton(
        title: String,
        icon: Image,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Design.Spacing._sm) {
                icon
                    .zImage(
                        width: Constants.actionIconSize,
                        height: Constants.actionIconSize,
                        style: ZappColors.text
                    )

                Text(title)
                    .zappFont(.buttonSmall, style: ZappColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(Design.Spacing._md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.actionMinHeight)
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(title)
    }

    @ViewBuilder private func bulletpoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.textSubtle.color(colorScheme))
                .frame(width: 4, height: 4)
                .padding(.top, Design.Spacing._md)

            Text(text)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder func helpSheetContent(_ colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xl) {
            Text(localizable: .depositFundsTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Spacing._4xl)

            Text(localizable: .depositFundsDesc)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            bulletpoint(String(localizable: .depositFundsBulletPoint1))
            bulletpoint(String(localizable: .depositFundsBulletPoint2))
            bulletpoint(String(localizable: .depositFundsBulletPoint3))

            ZappButton(title: String(localizable: .generalOk)) {
                store.send(.closeDepositHelpSheetTapped)
            }
            .padding(.top, Design.Spacing._xl)
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder func tokenTicker(asset: SwapAsset?, _ colorScheme: ColorScheme) -> some View {
        if let asset {
            asset.tokenIcon
                .resizable()
                .frame(width: Constants.tickerSize, height: Constants.tickerSize)
                .overlay(alignment: .bottomTrailing) {
                    asset.chainIcon
                        .resizable()
                        .frame(width: Constants.tickerBadgeSize, height: Constants.tickerBadgeSize)
                        .background(ZappColors.bg.color(colorScheme))
                        .offset(x: 5, y: 5)
                }
        }
    }

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
        if let addressToShare = store.addressToShare,
           let cgImg = QRCodeGenerator.generateCode(
            from: addressToShare.data,
            vendor: .zashi,
            color: .black,
            overlayedWithZcashLogo: false
           ) {
            UIShareDialogView(activityItems: [
                ShareableImage(
                    image: UIImage(cgImage: cgImg),
                    title: String(localizable: .swapToZecShareTitle),
                    reason: String(localizable: .swapToZecShareMsg(store.swapToZecAmountInQuotePreciseCopy, store.shareAssetName))
                ), String(localizable: .swapToZecShareMsg(store.swapToZecAmountInQuotePreciseCopy, store.shareAssetName))
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
