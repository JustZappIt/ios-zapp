// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct PortfolioChartSetupView: View {
    @Environment(\.colorScheme)
    private var colorScheme
    let store: StoreOf<PortfolioChartSetup>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .settingsPortfolioChartTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        ZappSettingsGroup(title: String(localizable: .settingsPortfolioChartSection)) {
                            ZappToggleRow(
                                title: String(localizable: .settingsPortfolioChartToggleTitle),
                                subtitle: String(localizable: .settingsPortfolioChartToggleSubtitle),
                                icon: Asset.Assets.Icons.currencyDollar.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: store.isEnabled
                            ) {
                                store.send(.enabledToggled)
                            }
                        }

                        Text(String(localizable: .settingsPortfolioChartFooter))
                            .zappFont(.caption, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Design.Spacing._2xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Design.Spacing._2xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                primaryAction: {
                    ZappButton(
                        title: String(localizable: .settingsPortfolioChartSave),
                        isEnabled: !store.isSaveButtonDisabled
                    ) {
                        store.send(.saveChangesTapped)
                    }
                },
                customDismiss: { store.send(.backToHomeTapped) }
            )
            .onAppear { store.send(.onAppear) }
        }
    }
}
