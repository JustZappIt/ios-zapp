//
//  AddressDetailsView.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-19-2024.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct AddressDetailsView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let qrSize: CGFloat = 216
        static let qrPadding: CGFloat = 24
        static let copyConfirmDuration: TimeInterval = 1.5
        static let iconSize: CGFloat = 20
    }

    @Perception.Bindable var store: StoreOf<AddressDetails>

    @State private var copyConfirmed = false

    init(store: StoreOf<AddressDetails>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: store.addressTitle,
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(spacing: 0) {
                        qrPanel

                        PrivacyBadge(store.maxPrivacy ? .max : .low)
                            .padding(.top, Design.Spacing._4xl)

                        Text(store.address.data)
                            .zappFont(.mono, style: ZappColors.textMuted)
                            .lineLimit(store.isAddressExpanded ? nil : 2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.center)
                            .padding(.top, Design.Spacing._lg)
                            .onTapGesture {
                                store.send(.addressTapped)
                            }
                            .onLongPressGesture {
                                store.send(.copyToPastboard)
                            }

                        copyButton
                            .padding(.top, Design.Spacing._xl)
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
                    title: String(localizable: .addressDetailsShareQR),
                    isEnabled: store.addressToShare == nil,
                    leadingIcon: Asset.Assets.Icons.share.image
                ) {
                    store.send(.shareQR)
                }
            })
            .enlargeQR(isPresented: $store.isQRCodeEnlarged) {
                qrEnlargedCode(store.address.data)
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
        qrCode(store.address.data)
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

    private var copyButton: some View {
        ZappButton(
            title: copyConfirmed
                ? String(localizable: .newChatCopied)
                : String(localizable: .addressDetailsCopyAddress),
            variant: copyConfirmed ? .secondary : .ghost,
            leadingIcon: copyConfirmed
                ? Asset.Assets.Icons.checkSolid.image
                : Asset.Assets.copy.image
        ) {
            store.send(.copyToPastboard)

            withAnimation(ZappMotion.content) {
                copyConfirmed = true
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.copyConfirmDuration * 1_000_000_000))

                withAnimation(ZappMotion.content) {
                    copyConfirmed = false
                }
            }
        }
    }
}

extension AddressDetailsView {
    @ViewBuilder func qrCode(_ qrText: String) -> some View {
        Group {
            if let storedImg = store.storedQR {
                Image(storedImg, scale: 1, label: Text(localizable: .qrCodeFor(qrText)))
                    .resizable()
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder func qrEnlargedCode(_ qrText: String) -> some View {
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
            maxPrivacy: store.maxPrivacy,
            vendor: .zashi,
            color: .black
           ) {
            UIShareDialogView(activityItems: [
                ShareableImage(
                    image: UIImage(cgImage: cgImg),
                    title: String(localizable: .addressDetailsShareTitle),
                    reason: String(localizable: .addressDetailsShareDesc)
                ), String(localizable: .addressDetailsShareDesc)
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
        AddressDetailsView(
            store: StoreOf<AddressDetails>(
                initialState: AddressDetails.State(address: "u1steuf7460a4m3svyyzlg3m6xlc6xd0q5qq7n0da8m29x0vcqdeuvjyw4h82a69vg8zn43cszudgfva45d2ju46227vc0dy0f73mzdv5dsz4wfmfrkaw3ycmd4qkg9hxh3arcrh2f9fdj02d42shg7fl5elvnqed4cq4t3sxu4spcx7cd4l8ye3e5ym9njj0hhs82gf7tjre4umqa2q6".redacted)
            ) {
                AddressDetails()
            }
        )
    }
}

// MARK: - Placeholders

extension AddressDetails.State {
    static var initial: AddressDetails.State { AddressDetails.State() }
}

extension AddressDetails {
    @MainActor static let placeholder = StoreOf<AddressDetails>(
        initialState: .initial
    ) {
        AddressDetails()
    }
}
