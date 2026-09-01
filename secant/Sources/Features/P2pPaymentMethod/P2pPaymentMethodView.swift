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
            title: "",
            titleLogo: Asset.Assets.Icons.providerPeer.image,
            titleLogoLabel: String(localizable: .p2pProviderPeer)
        ) {
            // Why the rails are dimmed, on the rows it applies to. The chip Android shows here is a
            // per-method liquidity flag, which is a different fact and would read as "not shipped".
            if let reason = unavailableReason {
                groupNote(reason)
            }

            if store.isPeerLoading {
                groupPlaceholder(String(localizable: .peerFormBalancePending))
            }

            ForEach(Array(store.destinations.enumerated()), id: \.element.id) { index, destination in
                if index > 0 || unavailableReason != nil { ZappRowDivider(inset: false) }
                selectableRow(
                    title: destination.displayName,
                    // Every currency the rail takes, truncated by the row rather than pre-trimmed:
                    // "and 8 more" tells the user less than the codes themselves do.
                    subtitle: destination.currencyCodes.joined(separator: ", "),
                    logo: destination.logo,
                    rail: .peerCashOut(destinationCode: destination.code),
                    isEnabled: store.canSelectPeer
                )
            }
        }
    }

    private var scanAndPayGroup: some View {
        ZappSettingsGroup(
            title: "",
            titleLogo: Asset.Assets.Icons.providerP2pMe.image,
            titleLogoLabel: String(localizable: .p2pProviderP2pme)
        ) {
            if store.isScanAndPayLoading {
                groupPlaceholder(String(localizable: .peerFormBalancePending))
            }

            ForEach(Array(store.corridors.enumerated()), id: \.element.id) { index, corridor in
                if index > 0 { ZappRowDivider(inset: false) }
                selectableRow(
                    title: "\(corridor.flag) \(corridor.countryName)",
                    subtitle: "\(corridor.paymentRail) · \(corridor.currencyCode)",
                    rail: .scanAndPay(currencyCode: corridor.currencyCode),
                    isEnabled: true
                )
            }
        }
    }

    /// A group with no rows still draws its border, so an empty one has to say why it is empty.
    private func groupPlaceholder(_ text: String) -> some View {
        Text(text)
            .zappFont(.caption, style: ZappColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }

    private func groupNote(_ text: String) -> some View {
        Text(text)
            .zappFont(.caption, style: ZappColors.accentText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(ZappColors.accentSoft.color(colorScheme))
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
            subtitleLineLimit: 1,
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

            if let address = store.baseAddress {
                baseAddressCard(address)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zappInfoSheet { isInfoPresented = false }
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
