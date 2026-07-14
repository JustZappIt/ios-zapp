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
        static let actionMinHeight: CGFloat = 64
        static let infoIconSize: CGFloat = 16
        static let infoBox: CGFloat = 32
        static let warningIconSize: CGFloat = 24
        static let qrSize: CGFloat = 260
        static let copyButtonSize: CGFloat = 40
    }

    /// One switcher segment. `actionAddress` is kept apart from the displayed `address` because
    /// upstream renders the Keystone account's own transparent address but copies/shares
    /// `store.transparentAddress`; that asymmetry is preserved rather than silently reconciled.
    private struct AddressSegment {
        let focus: Receive.State.AddressType
        let label: String
        let title: String
        let address: String
        let actionAddress: String
        let isShielded: Bool
        let canCopy: Bool
    }

    @Perception.Bindable var store: StoreOf<Receive>
    let networkType: NetworkType
    let tokenName: String

    @State var explainer = false
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
            .zashiSheet(isPresented: $explainer) {
                explainerContent()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: String(localizable: .tabsReceiveZec))

            if let segment = selectedSegment {
                ScrollView {
                    VStack(spacing: Design.Spacing._xl) {
                        ReceiveAddressQRCode(address: segment.actionAddress)
                            .frame(width: Constants.qrSize, height: Constants.qrSize)
                            .padding(Design.Spacing._md)
                            .background(Color.white)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                            )

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

                ShareLink(item: segment.actionAddress) {
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
                        store.send(.requestTapped(segment.actionAddress.redacted, segment.isShielded))
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
                title: isKeystone
                    ? String(localizable: .accountsKeystoneShieldedAddress)
                    : String(localizable: .accountsZashiShieldedAddress),
                address: store.unifiedAddress,
                actionAddress: store.unifiedAddress,
                isShielded: true,
                canCopy: true
            )
        ]

        if isKeystone {
            if let transparentAddress = store.selectedWalletAccount?.transparentAddress {
                result.append(
                    AddressSegment(
                        focus: .tAddress,
                        label: String(localizable: .zappPayTransparent),
                        title: String(localizable: .accountsKeystoneTransparentAddress),
                        address: transparentAddress,
                        actionAddress: store.transparentAddress,
                        isShielded: false,
                        canCopy: false
                    )
                )
            }
        } else {
            result.append(
                AddressSegment(
                    focus: .tAddress,
                    label: String(localizable: .zappPayTransparent),
                    title: String(localizable: .accountsZashiTransparentAddress),
                    address: store.transparentAddress,
                    actionAddress: store.transparentAddress,
                    isShielded: false,
                    canCopy: false
                )
            )

            #if DEBUG
            if networkType == .testnet {
                result.append(
                    AddressSegment(
                        focus: .saplingAddress,
                        label: String(localizable: .receiveSaplingAddress),
                        title: String(localizable: .receiveSaplingAddress),
                        address: store.saplingAddress,
                        actionAddress: store.saplingAddress,
                        isShielded: true,
                        canCopy: true
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
            store.send(.copyToPastboard(segment.actionAddress.redacted))
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

    private func addressPanel(_ segment: AddressSegment) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            HStack(spacing: Design.Spacing._md) {
                ZappSectionLabel(text: segment.title)

                Spacer(minLength: 0)

                Button {
                    store.send(.infoTapped(segment.isShielded))
                    explainer = true
                } label: {
                    Asset.Assets.infoCircle.image
                        .zImage(
                            width: Constants.infoIconSize,
                            height: Constants.infoIconSize,
                            style: ZappColors.textMuted
                        )
                        .frame(width: Constants.infoBox, height: Constants.infoBox)
                        .background(ZappColors.surfaceAlt.color(colorScheme))
                }
                .buttonStyle(.zappPress)
            }

            Text(segment.address)
                .zappFont(.mono, style: ZappColors.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    private func actionRow(_ segment: AddressSegment) -> some View {
        HStack(spacing: Design.Spacing._md) {
            if segment.canCopy {
                copyAction(segment)
            }

            actionButton(
                title: String(localizable: .receiveQrCode),
                icon: Asset.Assets.Icons.qr.image
            ) {
                store.send(.addressDetailsRequest(segment.actionAddress.redacted, segment.isShielded))
            }

            actionButton(
                title: String(localizable: .receiveRequest),
                icon: Asset.Assets.Icons.coinsHand.image
            ) {
                store.send(.requestTapped(segment.actionAddress.redacted, segment.isShielded))
            }
        }
    }

    private func copyAction(_ segment: AddressSegment) -> some View {
        actionButton(
            title: copyConfirmed
                ? String(localizable: .newChatCopied)
                : String(localizable: .receiveCopy),
            icon: copyConfirmed
                ? Asset.Assets.Icons.checkSolid.image
                : Asset.Assets.copy.image,
            tint: copyConfirmed ? .success : .text
        ) {
            store.send(.copyToPastboard(segment.actionAddress.redacted))

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

    private func actionButton(
        title: String,
        icon: Image,
        tint: ZappColors = .text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Design.Spacing._sm) {
                icon
                    .zImage(
                        width: Constants.actionIconSize,
                        height: Constants.actionIconSize,
                        style: tint
                    )

                Text(title)
                    .zappFont(.buttonSmall, style: tint)
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

    private var privacyWarning: some View {
        VStack(spacing: Design.Spacing._md) {
            Asset.Assets.shieldTick.image
                .zImage(
                    width: Constants.warningIconSize,
                    height: Constants.warningIconSize,
                    style: ZappColors.textSubtle
                )

            Text(localizable: .receiveWarning)
                .zappFont(.caption, style: ZappColors.textSubtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Design.Spacing._6xl)
        .padding(.bottom, Design.Spacing._2xl)
    }

    @ViewBuilder private func explainerContent() -> some View {
        VStack(spacing: 0) {
            if store.isExplainerForShielded {
                explainerBody(
                    icon: Asset.Assets.Icons.shieldTickFilled.image,
                    title: String(localizable: .receiveHelpShieldedTitle),
                    points: [
                        String(localizable: .receiveHelpShieldedDesc1),
                        String(localizable: .receiveHelpShieldedDesc2),
                        String(localizable: .receiveHelpShieldedDesc3),
                        String(localizable: .receiveHelpShieldedDesc4)
                    ],
                    isShielded: true
                )
            } else {
                explainerBody(
                    icon: Asset.Assets.Icons.shieldOff.image,
                    title: String(localizable: .receiveHelpTransparentTitle),
                    points: [
                        String(localizable: .receiveHelpTransparentDesc1),
                        String(localizable: .receiveHelpTransparentDesc2),
                        String(localizable: .receiveHelpTransparentDesc3),
                        String(localizable: .receiveHelpTransparentDesc4)
                    ],
                    isShielded: false
                )
            }
        }
    }

    private func explainerBody(
        icon: Image,
        title: String,
        points: [String],
        isShielded: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            icon
                .zImage(width: 20, height: 20, style: ZappColors.text)
                .frame(width: 44, height: 44)
                .background(ZappColors.surfaceAlt.color(colorScheme))
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._lg)

            Text(title)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._lg)

            ForEach(points, id: \.self) { point in
                infoContent(text: point)
                    .padding(.bottom, Design.Spacing._lg)
            }

            ZappButton(title: String(localizable: .generalOk)) {
                store.send(.infoTapped(isShielded))
                explainer = false
            }
            .padding(.top, Design.Spacing._2xl)
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func infoContent(text: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.textSubtle.color(colorScheme))
                .frame(width: 4, height: 4)
                .padding(.top, Design.Spacing._md)

            if let attrText = try? AttributedString(
                markdown: text,
                including: \.zashiApp
            ) {
                ZashiText(withAttributedString: attrText, colorScheme: colorScheme)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
