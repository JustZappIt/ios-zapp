//
//  ZappSyncErrorSheet.swift
//  Zapp
//
//  The Pay tab's actionable sync-error surface, mirroring Android's `SyncErrorView.kt`.
//
//  Android raises this sheet two ways: automatically, once per session, from
//  `HomeVM.uiLifecyclePipeline`, and on demand when the user taps the error message on the wallet
//  home. iOS had the second half of this built already — `SmartBanner.State` carries
//  `isSyncTimedOutSheetPresented` and every action here already clears it — but the only view that
//  ever presented it lived in `SmartBannerView`, which the Zapp tab shell does not mount. This is
//  the Zapp-side presentation of that existing state; the reducer is untouched.
//
//  Copy and action set follow `SyncErrorView.kt`: try again / switch server / disable Tor /
//  contact support.
//

import SwiftUI

struct ZappSyncErrorSheet: View {
    private enum Constants {
        static let iconSize: CGFloat = 24
        static let headerIconSize: CGFloat = 28
        static let rowVerticalPadding: CGFloat = 16
        static let rowHorizontalPadding: CGFloat = 16
        static let dividerInset: CGFloat = 8
        static let height: CGFloat = 430
    }

    @Environment(\.colorScheme) private var colorScheme

    /// The raw synchronizer message. Android puts the stack trace in the *generic* error sheet
    /// rather than this one, so it stays out of the body copy and travels with the support report.
    let errorMessage: String
    let onTryAgain: () -> Void
    let onSwitchServer: () -> Void
    let onDisableTor: () -> Void
    let onContactSupport: () -> Void

    static var detentHeight: CGFloat { Constants.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 0) {
                // Android's first and most-used remedy: reset the synchronizer and resync.
                row(
                    icon: Asset.Assets.Icons.refreshSingleCCW.image,
                    label: String(localizable: .sheetSyncTimeoutRetry),
                    action: onTryAgain
                )

                divider

                row(
                    icon: Asset.Assets.Icons.server.image,
                    label: String(localizable: .sheetSyncTimeoutServer),
                    action: onSwitchServer
                )

                divider

                // Android hides this row when Tor is already off. iOS has no Tor flag on
                // `SmartBanner.State`, and the pre-existing upstream sheet showed the row
                // unconditionally too, so this keeps that behaviour rather than adding a
                // dependency for it.
                row(
                    icon: Asset.Assets.Icons.powerOff.image,
                    label: String(localizable: .sheetSyncTimeoutTor),
                    action: onDisableTor
                )
            }
            .padding(.top, Design.Spacing._xl)

            Spacer(minLength: Design.Spacing._xl)

            ZappButton(title: String(localizable: .errorPageActionContactSupport)) {
                onContactSupport()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            Asset.Assets.Icons.alertTriangle.image
                .zImage(
                    width: Constants.headerIconSize,
                    height: Constants.headerIconSize,
                    style: ZappColors.danger
                )

            Text(String(localizable: .sheetSyncTimeoutTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(String(localizable: .sheetSyncTimeoutDesc))
                .zappFont(.caption, style: ZappColors.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(height: 1)
            .padding(.horizontal, Constants.dividerInset)
    }

    private func row(icon: Image, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing._xl) {
                icon
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accent)

                Text(label)
                    .zappFont(.rowTitle, style: ZappColors.text)

                Spacer()
            }
            .padding(.horizontal, Constants.rowHorizontalPadding)
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(label)
    }
}
