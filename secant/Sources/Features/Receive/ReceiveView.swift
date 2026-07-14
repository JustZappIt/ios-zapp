//
//  ReceiveView.swift
//  Zashi
//
//  Created by Lukáš Korba on 05.07.2022.
//

import SwiftUI
import ComposableArchitecture
import UIKit
@preconcurrency import ZcashLightClientKit

struct ReceiveView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let copyConfirmDuration: TimeInterval = 1.5
        static let actionIconSize: CGFloat = 20
        static let qrMaxSize: CGFloat = 300
        static let copyButtonSize: CGFloat = 40
    }

    /// One switcher segment. A single address is the source for display, QR, copy, share, and request.
    private struct AddressSegment {
        let focus: Receive.State.AddressType
        let label: String
        let address: String
        let isShielded: Bool
    }

    @Perception.Bindable var store: StoreOf<Receive>
    let networkType: NetworkType
    let tokenName: String

    @State private var copyConfirmed = false

    init(store: StoreOf<Receive>, networkType: NetworkType, tokenName: String) {
        self.store = store
        self.networkType = networkType
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                WithPerceptionTracking {
                    content
                }
            } destination: { store in
                switch store.case {
                case let .addressDetails(store):
                    AddressDetailsView(store: store)
                case let .requestZec(store):
                    RequestZecView(store: store, tokenName: tokenName)
                case let .requestZecSummary(store):
                    RequestZecSummaryView(store: store, tokenName: tokenName)
                case let .zecKeyboard(store):
                    ZecKeyboardView(store: store, tokenName: tokenName)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: String(localizable: .tabsReceiveZec))

            if let segment = selectedSegment {
                ScrollView {
                    VStack(spacing: Design.Spacing._xl) {
                        GeometryReader { proxy in
                            let size = min(
                                max(0, proxy.size.width - (Design.Spacing._md * 2)),
                                Constants.qrMaxSize
                            )

                            ReceiveAddressQRCode(address: segment.address)
                                .frame(width: size, height: size)
                                .padding(Design.Spacing._md)
                                .background(Color.white)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: Constants.qrMaxSize + (Design.Spacing._md * 2))

                        HStack(alignment: .top, spacing: Design.Spacing._md) {
                            Text(segment.address)
                                .zappFont(.mono, style: ZappColors.textMuted)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            copyIconButton(segment)
                        }

                        HStack(alignment: .top, spacing: Design.Spacing._md) {
                            Rectangle()
                                .fill(ZappColors.accent.color(colorScheme))
                                .frame(width: 3, height: 36)

                            Text(localizable: .receiveWarning)
                                .zappFont(.caption, style: ZappColors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, Design.Spacing._3xl)
                    .padding(.top, Design.Spacing._xl)
                }
                .frame(maxHeight: .infinity)

                if segments.count > 1 {
                    ZappSegmentedSelector(
                        options: segments.map(\.label),
                        selectedIndex: selectedIndex
                    ) { index in
                        store.send(.updateCurrentFocus(segments[index].focus), animation: .default)
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.vertical, Design.Spacing._sm)
                }

                ShareLink(item: segment.address) {
                    Text(String(localizable: .generalShare).uppercased())
                        .zappFont(.button, style: ZappColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            Rectangle()
                                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                        )
                }
                .buttonStyle(.zappPress)
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.bottom, Design.Spacing._sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .onAppear { store.send(.updateCurrentFocus(.uaAddress)) }
        .zashiBack(
            primaryAction: {
                if let segment = selectedSegment {
                    ZappButton(title: String(localizable: .receiveRequest)) {
                        store.send(.requestTapped(segment.address.redacted, segment.isShielded))
                    }
                }
            },
            customDismiss: { store.send(.backToHomeTapped) }
        )
    }

    private var segments: [AddressSegment] {
        let isKeystone = store.selectedWalletAccount?.vendor == .keystone

        var result: [AddressSegment] = [
            AddressSegment(
                focus: .uaAddress,
                label: String(localizable: .zappPayShielded),
                address: store.unifiedAddress,
                isShielded: true
            )
        ]

        if isKeystone {
            if let transparentAddress = store.selectedWalletAccount?.transparentAddress {
                result.append(
                    AddressSegment(
                        focus: .tAddress,
                        label: String(localizable: .zappPayTransparent),
                        address: transparentAddress,
                        isShielded: false
                    )
                )
            }
        } else {
            result.append(
                AddressSegment(
                    focus: .tAddress,
                    label: String(localizable: .zappPayTransparent),
                    address: store.transparentAddress,
                    isShielded: false
                )
            )

            #if DEBUG
            if networkType == .testnet {
                result.append(
                    AddressSegment(
                        focus: .saplingAddress,
                        label: String(localizable: .receiveSaplingAddress),
                        address: store.saplingAddress,
                        isShielded: true
                    )
                )
            }
            #endif
        }

        return result
    }

    private var selectedIndex: Int {
        segments.firstIndex { $0.focus == store.currentFocus } ?? 0
    }

    private var selectedSegment: AddressSegment? {
        let all = segments

        return all.indices.contains(selectedIndex) ? all[selectedIndex] : all.first
    }

    private func copyIconButton(_ segment: AddressSegment) -> some View {
        Button {
            store.send(.copyToPastboard(segment.address.redacted))
            withAnimation(ZappMotion.content) { copyConfirmed = true }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.copyConfirmDuration * 1_000_000_000))
                withAnimation(ZappMotion.content) { copyConfirmed = false }
            }
        } label: {
            (copyConfirmed ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image)
                .zImage(
                    width: Constants.actionIconSize,
                    height: Constants.actionIconSize,
                    style: copyConfirmed ? ZappColors.success : ZappColors.accentText
                )
                .frame(width: Constants.copyButtonSize, height: Constants.copyButtonSize)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            (copyConfirmed ? ZappColors.success : ZappColors.border).color(colorScheme),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(String(localizable: .receiveCopy))
    }
}

private struct ReceiveAddressQRCode: View {
    let address: String

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .task(id: address) {
            guard !address.isEmpty else {
                image = nil
                return
            }

            image = await QRCodeGenerator.generate(
                from: address,
                maxPrivacy: false,
                color: .black,
                overlayedWithZcashLogo: true
            )
        }
    }
}

#Preview {
    NavigationView {
        ReceiveView(store: Receive.placeholder, networkType: .testnet, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension Receive.State {
    static var initial: Receive.State { Receive.State() }
}

extension Receive {
    @MainActor static let placeholder = StoreOf<Receive>(
        initialState: .initial
    ) {
        Receive()
    }
}
