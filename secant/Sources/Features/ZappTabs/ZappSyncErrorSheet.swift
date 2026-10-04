//
//  ZappSyncErrorSheet.swift
//  Zapp
//
//  The Pay tab's actionable sync-error surface, mirroring Android's `SyncErrorView.kt`.
//
//  Android raises this sheet two ways: automatically, once per error episode, from
//  `HomeVM.uiLifecyclePipeline` (`Home.hasZappSyncErrorEpisodeBeenShown` here, plus the existing
//  `SmartBanner` sync-timeout flag), and on demand when the user taps the progress row.
//
//  Copy and action set follow `SyncErrorVM.kt`: the generic "Something went wrong" instruction,
//  then try again and switch server (always both), disable Tor (only while Tor is on), and contact
//  support. The raw SDK message is not the body; it stays as a short secondary line so a support
//  screenshot still carries the error code.
//

import SwiftUI

struct ZappSyncErrorSheet: View {
    enum Remedy: Equatable {
        case retry
        case switchServer
        case disableTor
    }

    private enum Constants {
        static let iconSize: CGFloat = 24
        static let headerIconSize: CGFloat = 28
        static let rowVerticalPadding: CGFloat = 16
        static let rowHorizontalPadding: CGFloat = 16
        static let dividerInset: CGFloat = 8
        static let errorDetailLineLimit = 3
        static let height: CGFloat = 540
    }

    @Environment(\.colorScheme) private var colorScheme

    let errorMessage: String
    let isTorEnabled: Bool
    let onTryAgain: () -> Void
    let onSwitchServer: () -> Void
    let onDisableTor: () -> Void
    let onContactSupport: () -> Void

    static var detentHeight: CGFloat { Constants.height }

    /// Android's `SyncErrorVM.createState`: both recovery routes every time, Tor only when on.
    static func remedies(isTorEnabled: Bool) -> [Remedy] {
        isTorEnabled ? [.retry, .switchServer, .disableTor] : [.retry, .switchServer]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(spacing: 0) {
                        let remedies = Self.remedies(isTorEnabled: isTorEnabled)
                        ForEach(Array(remedies.enumerated()), id: \.offset) { index, remedy in
                            if index > 0 {
                                divider
                            }
                            row(for: remedy)
                        }
                    }
                    .padding(.top, Design.Spacing._xl)
                }
            }

            ZappButton(title: String(localizable: .errorPageActionContactSupport)) {
                onContactSupport()
            }
            .padding(.top, Design.Spacing._xl)
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

            Text(localizable: .sheetSyncTimeoutTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(localizable: .sheetSyncTimeoutDesc)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .zappFont(.caption, style: ZappColors.textSubtle)
                    .lineLimit(Constants.errorDetailLineLimit)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private func row(for remedy: Remedy) -> some View {
        switch remedy {
        case .retry:
            row(
                icon: Asset.Assets.Icons.refreshSingleCCW.image,
                label: String(localizable: .sheetSyncTimeoutRetry),
                action: onTryAgain
            )
        case .switchServer:
            row(
                icon: Asset.Assets.Icons.server.image,
                label: String(localizable: .sheetSyncTimeoutServer),
                action: onSwitchServer
            )
        case .disableTor:
            row(
                icon: Asset.Assets.Icons.powerOff.image,
                label: String(localizable: .sheetSyncTimeoutTor),
                action: onDisableTor
            )
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
