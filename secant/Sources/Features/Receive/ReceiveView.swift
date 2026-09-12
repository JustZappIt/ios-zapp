//
//  ReceiveView.swift
//  Zashi
//
//  Created by Lukáš Korba on 05.07.2022.
//

import SwiftUI
import ComposableArchitecture
import UIKit

struct ReceiveView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let copyConfirmDuration: TimeInterval = 1.5
        static let actionIconSize: CGFloat = 20
        static let qrMaxSize: CGFloat = 300
        static let copyButtonSize: CGFloat = 40
        static let tipBarHeight: CGFloat = 36
        static let explainerIconSize: CGFloat = 20
        static let explainerIconBox: CGFloat = 40
    }

    /// One switcher segment. A single address is the source for display, QR, copy, share, and request.
    private struct AddressSegment {
        let focus: Receive.State.AddressType
        let label: String
        let address: String
        let isShielded: Bool
    }

    @Perception.Bindable var store: StoreOf<Receive>
    let tokenName: String

    @State private var copyConfirmed = false

    init(store: StoreOf<Receive>, tokenName: String) {
        self.store = store
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
                }
            }
            .navigationBarHidden(true)
            // Rises from the bottom and drops back down, matching Android's
            // `sheetEnterTransition` for its `REQUEST` route. Receive itself stays a push.
            .fullScreenCover(item: $store.scope(state: \.requestFlow, action: \.requestFlow)) { flowStore in
                WithPerceptionTracking {
                    ReceiveRequestFlowView(store: flowStore, tokenName: tokenName)
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: String(localizable: .tabsReceiveZec)) {
                // Android keeps the address-type explainer behind an info action; the Zapp
                // rewrite had dropped the entry point and left only the one-line tip.
                ZappInfoButton(accessibilityLabel: String(localizable: .receiveHelpInfoAccessibility)) {
                    store.send(.infoTapped(selectedSegment?.isShielded ?? true))
                }
            }

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

                        // Android's Swiss tip block: eyebrow over the one-line rule.
                        HStack(alignment: .top, spacing: Design.Spacing._md) {
                            Rectangle()
                                .fill(ZappColors.accent.color(colorScheme))
                                .frame(width: 3, height: Constants.tipBarHeight)

                            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                                Text(String(localizable: .receiveTipLabel))
                                    .zappFont(.eyebrow, style: ZappColors.textSubtle)

                                Text(localizable: .receiveWarning)
                                    .zappFont(.caption, style: ZappColors.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
        // Mounted here, not on the NavigationStack, which already owns the Request fullScreenCover.
        .sheet(isPresented: explainerBinding) {
            WithPerceptionTracking { explainerSheet }
        }
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

    /// `.infoTapped` toggles, so a swipe-down and the sheet's own button both send it once.
    private var explainerBinding: Binding<Bool> {
        Binding(
            get: { store.isAddressExplainerPresented },
            set: { isPresented in
                if !isPresented && store.isAddressExplainerPresented {
                    store.send(.infoTapped(store.isExplainerForShielded))
                }
            }
        )
    }

    /// Android's `ShieldedAddressInfoScreen` / `TransparentAddressInfoScreen`: icon, title, four
    /// bullets, one dismiss button.
    private var explainerSheet: some View {
        let isShielded = store.isExplainerForShielded
        let bullets: [String] = isShielded
            ? [
                String(localizable: .receiveHelpShieldedDesc1),
                String(localizable: .receiveHelpShieldedDesc2),
                String(localizable: .receiveHelpShieldedDesc3),
                String(localizable: .receiveHelpShieldedDesc4)
            ]
            : [
                String(localizable: .receiveHelpTransparentDesc1),
                String(localizable: .receiveHelpTransparentDesc2),
                String(localizable: .receiveHelpTransparentDesc3),
                String(localizable: .receiveHelpTransparentDesc4)
            ]

        return VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            (isShielded ? Asset.Assets.Icons.shieldTickFilled.image : Asset.Assets.Icons.shieldOff.image)
                .zImage(width: Constants.explainerIconSize, height: Constants.explainerIconSize, style: ZappColors.accentText)
                .frame(width: Constants.explainerIconBox, height: Constants.explainerIconBox)
                .background(ZappColors.accentSoft.color(colorScheme))

            Text(isShielded
                ? String(localizable: .receiveHelpShieldedTitle)
                : String(localizable: .receiveHelpTransparentTitle)
            )
            .zappFont(.sectionTitle, style: ZappColors.text)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: Design.Spacing._md) {
                    Text(verbatim: "•")
                        .zappFont(.body, style: ZappColors.textMuted)

                    Text(bullet)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zappInfoSheet { store.send(.infoTapped(isShielded)) }
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
        ReceiveView(store: Receive.placeholder, tokenName: "ZEC")
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
