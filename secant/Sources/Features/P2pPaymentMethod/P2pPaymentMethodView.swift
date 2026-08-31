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

                ZappBottomActionBar(onBack: { store.send(.backTapped) })
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    /// Cash-out first: it is the newer product and the one a user arriving from Pay is least likely
    /// to expect, so it is the group they read rather than the one they scroll past.
    private var cashOutGroup: some View {
        ZappSettingsGroup(title: String(localizable: .p2pPaymentMethodCashOutGroup)) {
            Text(String(localizable: .p2pPaymentMethodCashOutExplainer))
                .zappFont(.caption, style: ZappColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            if !store.isPeerAvailable {
                unavailableNote(String(localizable: .p2pPaymentMethodPeerNetwork))
            } else if !store.isSoftwareWallet {
                unavailableNote(String(localizable: .p2pPaymentMethodPeerHardwareWallet))
            }

            ForEach(store.destinations) { destination in
                selectableRow(
                    title: destination.displayName,
                    subtitle: destination.currencyCodes.joined(separator: " · "),
                    rail: .peerCashOut(destinationCode: destination.code),
                    isEnabled: store.canSelectPeer
                )
            }
        }
    }

    private var scanAndPayGroup: some View {
        ZappSettingsGroup(title: String(localizable: .p2pPaymentMethodScanAndPayGroup)) {
            Text(String(localizable: .p2pPaymentMethodScanAndPayExplainer))
                .zappFont(.caption, style: ZappColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            ForEach(store.corridors) { corridor in
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
        rail: P2pRail,
        isEnabled: Bool
    ) -> some View {
        let isSelected = store.selected == rail
        let displayedTitle = [leading, title].compactMap { $0 }.joined(separator: " ")
        return ZappSelectionRow(
            title: displayedTitle,
            subtitle: subtitle,
            isSelected: isSelected,
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
