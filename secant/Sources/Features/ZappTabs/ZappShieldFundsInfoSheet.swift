//
//  ZappShieldFundsInfoSheet.swift
//  Zapp
//
//  The "Always Shield Transparent Funds" explainer shown before the balance card's Shield, mirroring
//  Android's `ShieldFundsInfoView.kt`. The checkbox is the existing keychain-backed
//  `SmartBanner.State.isShieldingAcknowledged` flag, so it persists the moment it is toggled, as
//  Android's `ShieldFundsInfoProvider.flip()` does.
//

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

struct ZappShieldFundsInfoSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let iconSize: CGFloat = 28
        static let checkboxSize: CGFloat = 20
        static let checkIconSize: CGFloat = 11
        /// Used until the content has been measured.
        static let estimatedHeight: CGFloat = 520
    }

    @Perception.Bindable var store: StoreOf<SmartBanner>
    let onShield: () -> Void
    let onNotNow: () -> Void

    @State private var contentHeight = Constants.estimatedHeight

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Asset.Assets.shieldTick.image
                        .zImage(size: Constants.iconSize, style: ZappColors.accent)
                        .padding(.bottom, 12)

                    Text(localizable: .smartBannerHelpShieldTitle)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    Text(localizable: .smartBannerHelpShieldInfo1)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)

                    Text(localizable: .smartBannerHelpShieldInfo2(
                        "\(String(localizable: .generalFeeShort(store.feeStr))) \(store.tokenName)"
                    ))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)

                    ZappBorderedCard {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(localizable: .smartBannerHelpShieldTransparent)
                                    .zappFont(.rowTitle, style: ZappColors.text)

                                Asset.Assets.Icons.shieldOff.image
                                    .zImage(size: 16, style: ZappColors.text)
                            }

                            ZatoshiText(store.transparentBalance, .expanded, store.tokenName)
                                .zappFont(.sectionTitle, style: ZappColors.text)
                        }
                    }
                    .padding(.bottom, 16)

                    checkbox
                        .padding(.bottom, 20)

                    ZappButton(title: String(localizable: .smartBannerContentShieldButton), action: onShield)
                        .padding(.bottom, 8)

                    ZappButton(
                        title: String(localizable: .smartBannerHelpShieldNotNow),
                        variant: .ghost,
                        action: onNotNow
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
                .readHeight { height in
                    if height > 0, abs(height - contentHeight) > 1 {
                        contentHeight = height
                    }
                }
            }
            .zappFittedSheetDetent(contentHeight)
        }
    }

    private var checkbox: some View {
        Button {
            store.isShieldingAcknowledged.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Rectangle()
                        .fill((store.isShieldingAcknowledged ? ZappColors.accent : ZappColors.surface).color(colorScheme))
                        .overlay(
                            Rectangle().strokeBorder(
                                (store.isShieldingAcknowledged ? ZappColors.accent : ZappColors.borderStrong).color(colorScheme),
                                lineWidth: 1
                            )
                        )

                    if store.isShieldingAcknowledged {
                        Asset.Assets.Icons.checkSolid.image
                            .zImage(width: Constants.checkIconSize, height: Constants.checkIconSize, style: ZappColors.onAccent)
                    }
                }
                .frame(width: Constants.checkboxSize, height: Constants.checkboxSize)

                Text(localizable: .smartBannerHelpShieldDoNotShowAgain)
                    .zappFont(.body, style: ZappColors.text)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.isShieldingAcknowledged ? [.isButton, .isSelected] : .isButton)
    }
}
