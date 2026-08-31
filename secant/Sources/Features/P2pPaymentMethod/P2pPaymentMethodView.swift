// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct P2pPaymentMethodView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<P2pPaymentMethod>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .p2pPaymentMethodTitle))

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
            Text(String(localizable: .p2pPaymentMethodCashOutExplainer))
                .zappFont(.caption, style: ZappColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            // The account reason first: it is the more specific of the two and the only one the
            // user can act on. A hardware wallet cannot derive the Base account the rails sign
            // from, so the capability read reports them unavailable for that reason too.
            if !store.isSoftwareWallet {
                unavailableNote(String(localizable: .p2pPaymentMethodPeerHardwareWallet))
            } else if !store.isPeerAvailable {
                unavailableNote(String(localizable: .p2pPaymentMethodPeerNetwork))
            }

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
            Text(String(localizable: .p2pPaymentMethodScanAndPayExplainer))
                .zappFont(.caption, style: ZappColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            ForEach(Array(store.corridors.enumerated()), id: \.element.id) { index, corridor in
                if index > 0 { ZappRowDivider(inset: true) }
                selectableRow(
                    title: corridor.countryName,
                    subtitle: "\(corridor.paymentRail) · \(corridor.currencyCode)",
                    leading: corridor.flag,
                    rail: .scanAndPay(currencyCode: corridor.currencyCode),
                    isEnabled: true
                )
            }
        }
    }

    private func selectableRow(
        title: String,
        subtitle: String,
        leading: String? = nil,
        logo: Image? = nil,
        rail: P2pRail,
        isEnabled: Bool
    ) -> some View {
        let displayedTitle = [leading, title].compactMap { $0 }.joined(separator: " ")
        return ZappSelectionRow(
            title: displayedTitle,
            subtitle: subtitle,
            logo: logo,
            isSelected: store.selected == rail,
            isEnabled: isEnabled
        ) {
            store.send(.railTapped(rail))
        }
    }

    private func unavailableNote(_ text: String) -> some View {
        Text(text)
            .zappFont(.caption, style: ZappColors.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ZappColors.accentSoft.color(colorScheme))
            .padding(.horizontal, 14)
            .padding(.top, 10)
    }
}

#Preview {
    P2pPaymentMethodView(
        store: Store(initialState: P2pPaymentMethod.State.initial) { P2pPaymentMethod() }
    )
    .applyScreenBackground()
}
