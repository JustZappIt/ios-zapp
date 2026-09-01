// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct P2pPaymentMethodView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<P2pPaymentMethod>

    @State private var isInfoPresented = false

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .p2pPaymentMethodTitle)) {
                    ZappInfoButton(
                        accessibilityLabel: String(localizable: .p2pPaymentMethodInfoAccessibility)
                    ) { isInfoPresented = true }
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if let error = store.errorMessage {
                            Text(error)
                                .zappFont(.caption, style: ZappColors.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.bottom, Design.Spacing._lg)
                        }

                        cashOutGroup
                        scanAndPayGroup
                    }
                    .padding(.vertical, Design.Spacing._lg)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                    ZappButton(
                        title: String(localizable: .p2pPaymentMethodSave),
                        isEnabled: store.canSave
                    ) { store.send(.saveTapped) }
                }
            }
            .applyScreenBackground()
            .sheet(isPresented: $isInfoPresented) { infoSheet }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    /// Cash-out first: it is the newer product and the one a user arriving from Pay is least likely
    /// to expect, so it is the group they read rather than the one they scroll past.
    private var cashOutGroup: some View {
        ZappSettingsGroup(
            title: String(localizable: .p2pPaymentMethodCashOutGroup),
            titleLogo: Asset.Assets.Icons.providerPeer.image
        ) {
            ForEach(Array(store.destinations.enumerated()), id: \.element.id) { index, destination in
                if index > 0 { ZappRowDivider(inset: true) }
                selectableRow(
                    title: destination.displayName,
                    subtitle: destination.currencyCodes.joined(separator: " · "),
                    logo: destination.logo,
                    rail: .peerCashOut(destinationCode: destination.code),
                    isEnabled: store.canSelectPeer
                )
            }
        }
    }

    private var scanAndPayGroup: some View {
        ZappSettingsGroup(
            title: String(localizable: .p2pPaymentMethodScanAndPayGroup),
            titleLogo: Asset.Assets.Icons.providerP2pMe.image
        ) {
            ForEach(Array(store.corridors.enumerated()), id: \.element.id) { index, corridor in
                if index > 0 { ZappRowDivider(inset: true) }
                selectableRow(
                    title: "\(corridor.flag) \(corridor.countryName)",
                    subtitle: "\(corridor.paymentRail) · \(corridor.currencyCode)",
                    rail: .scanAndPay(currencyCode: corridor.currencyCode),
                    isEnabled: true
                )
            }
        }
    }

    private func selectableRow(
        title: String,
        subtitle: String,
        logo: Image? = nil,
        rail: P2pRail,
        isEnabled: Bool
    ) -> some View {
        ZappSelectionRow(
            title: title,
            subtitle: subtitle,
            logo: logo,
            trailingChip: isEnabled ? nil : String(localizable: .p2pPaymentMethodComingSoon),
            isSelected: store.selected == rail,
            isEnabled: isEnabled
        ) {
            store.send(.railTapped(rail))
        }
    }

    /// Everything that used to sit under the two group titles as running prose. Android keeps it
    /// behind the header's info button, and a list of rails reads better without it.
    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .p2pPaymentMethodInfoTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(String(localizable: .p2pPaymentMethodCashOutExplainer))
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localizable: .p2pPaymentMethodScanAndPayExplainer))
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if !store.canSelectPeer, let note = unavailableReason {
                Text(note)
                    .zappFont(.caption, style: ZappColors.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZappColors.accentSoft.color(colorScheme))
            }

            if let address = store.baseAddress {
                baseAddressCard(address)
            }

            Spacer()

            ZappButton(title: String(localizable: .peerFormInfoDismiss)) {
                isInfoPresented = false
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .applyScreenBackground()
        .presentationDetents([.medium, .large])
    }

    private func baseAddressCard(_ address: String) -> some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localizable: .p2pPaymentMethodInfoBaseLabel))
                    .zappFont(.caption, style: ZappColors.textMuted)

                HStack(spacing: 8) {
                    Text(address)
                        .zappFont(.mono, style: ZappColors.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZappCopyIconButton(
                        isCopied: store.isAddressCopied,
                        accessibilityLabel: String(localizable: .offrampAccountCopy)
                    ) {
                        store.send(.copyAddressTapped)
                    }
                }
            }
        }
    }

    /// The account reason first: it is the more specific of the two and the only one the user can
    /// act on.
    private var unavailableReason: String? {
        if !store.isSoftwareWallet {
            return String(localizable: .p2pPaymentMethodPeerHardwareWallet)
        }
        if !store.isPeerAvailable {
            return String(localizable: .p2pPaymentMethodPeerNetwork)
        }
        return nil
    }
}

#Preview {
    P2pPaymentMethodView(
        store: Store(initialState: P2pPaymentMethod.State.initial) { P2pPaymentMethod() }
    )
    .applyScreenBackground()
}
