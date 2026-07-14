//
//  ZappSyncStatus.swift
//  Zapp
//
//  The Pay tab's sync surface. Every value is read out of `SmartBanner.State`; the reducer is
//  untouched and the upstream `SmartBannerView` stays pristine.
//

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

enum ZappSyncState: Equatable {
    case offline
    case error
    case restoring
    case syncing
    case synced
    case connecting

    init(_ banner: SmartBanner.State) {
        if banner.priorityContent == .priority1 || banner.walletStatus == .disconnected {
            self = .offline
            return
        }

        switch banner.synchronizerStatusSnapshot.syncStatus {
        case .error:
            self = .error
        case .syncing:
            self = banner.walletStatus == .restoring ? .restoring : .syncing
        case .upToDate:
            self = .synced
        case .unprepared, .stopped:
            self = banner.walletStatus == .restoring ? .restoring : .connecting
        }
    }

    var label: String {
        switch self {
        case .offline: return String(localizable: .zappSyncOffline)
        case .error: return String(localizable: .zappSyncError)
        case .restoring: return String(localizable: .zappSyncRestoring)
        case .syncing: return String(localizable: .zappSyncSyncing)
        case .synced: return String(localizable: .zappSyncSynced)
        case .connecting: return String(localizable: .zappSyncConnecting)
        }
    }

    var variant: ZappChipVariant {
        switch self {
        case .offline, .error: return .danger
        case .restoring, .syncing: return .accent
        case .synced: return .success
        case .connecting: return .muted
        }
    }

    var dotColor: ZappColors {
        switch self {
        case .offline, .error: return .danger
        case .restoring, .syncing: return .accent
        case .synced: return .success
        case .connecting: return .textSubtle
        }
    }

    var showsProgress: Bool {
        self == .restoring || self == .syncing
    }
}

struct ZappSyncChip: View {
    let state: ZappSyncState

    var body: some View {
        ZappStatusChip(text: state.label, variant: state.variant, dotColor: state.dotColor)
    }
}

struct ZappSyncProgressRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let barHeight: CGFloat = 3
        static let horizontalPadding: CGFloat = 18
        static let spacing: CGFloat = 6
    }

    let state: ZappSyncState
    /// `SmartBanner.State.syncingPercentage`, already normalised to 0...1 by the reducer.
    let percentage: Double
    let errorMessage: String

    var body: some View {
        if state == .synced {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Constants.spacing) {
                if let detail {
                    Text(detail)
                        .zappFont(.caption, style: detailStyle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: detailAlignment)
                }

                bar
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.top, Constants.spacing)
            .padding(.bottom, 10)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))

                Rectangle()
                    .fill(state.dotColor.color(colorScheme))
                    .frame(width: proxy.size.width * fraction)
                    .animation(ZappMotion.content, value: fraction)
            }
        }
        .frame(height: Constants.barHeight)
    }

    private var fraction: CGFloat {
        switch state {
        case .restoring, .syncing: return CGFloat(min(max(percentage, 0), 1))
        case .offline, .error: return 1
        case .connecting, .synced: return 0
        }
    }

    private var detail: String? {
        if state.showsProgress {
            return String(format: "%.0f%%", min(max(percentage, 0), 1) * 100)
        }

        if state == .error, !errorMessage.isEmpty {
            return errorMessage
        }

        return nil
    }

    private var detailStyle: ZappColors {
        state.showsProgress ? .textMuted : .danger
    }

    private var detailAlignment: Alignment {
        state.showsProgress ? .trailing : .leading
    }
}

/// The actionable half of the smart banner: wallet backup, shielding, Tor, currency conversion.
///
/// Android drops these entirely. Not copied: wallet backup is a funds-loss surface and the Zapp
/// shell has no other entry point to it. The non-actionable priorities (disconnected, sync error,
/// restoring, syncing) are carried by the chip and the progress row instead.
struct ZappSmartActionStrip: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let iconSize: CGFloat = 20
        static let spacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 12
        static let outerPadding: CGFloat = 18
    }

    @Perception.Bindable var store: StoreOf<SmartBanner>

    var body: some View {
        WithPerceptionTracking {
            if store.isOpen, let action {
                HStack(spacing: Constants.spacing) {
                    action.icon
                        .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accentText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .zappFont(.rowTitle, style: ZappColors.text)
                            .lineLimit(1)

                        Text(action.info)
                            .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ZappButton(title: action.cta, variant: .accentGhost, isEnabled: action.isEnabled) {
                        store.send(action.event)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
                .background(ZappColors.surface.color(colorScheme))
                .overlay(
                    Rectangle()
                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                )
                .padding(.horizontal, Constants.outerPadding)
                .padding(.bottom, 20)
            }
        }
    }

    private var action: ZappSmartAction? {
        switch store.priorityContent {
        case .priority6:
            return ZappSmartAction(
                icon: Asset.Assets.Icons.alertTriangle.image,
                title: String(localizable: .smartBannerContentBackupTitle),
                info: String(localizable: .smartBannerContentBackupInfo),
                cta: String(localizable: .smartBannerContentBackupButton),
                event: .walletBackupTapped
            )
        case .priority7:
            return ZappSmartAction(
                icon: Asset.Assets.Icons.shieldOff.image,
                title: String(localizable: .smartBannerContentShieldTitle),
                info: "\(store.transparentBalance.decimalString()) \(store.tokenName)",
                cta: String(localizable: .smartBannerContentShieldButton),
                event: .shieldFundsTapped,
                isEnabled: !store.isShielding
            )
        case .priority75:
            return ZappSmartAction(
                icon: Asset.Assets.Icons.shieldZap.image,
                title: String(localizable: .smartBannerContentTorTitle),
                info: String(localizable: .smartBannerContentTorInfo),
                cta: String(localizable: .smartBannerContentTorButton),
                event: .torSetupTapped
            )
        case .priority8:
            return ZappSmartAction(
                icon: Asset.Assets.Icons.coinsSwap.image,
                title: String(localizable: .smartBannerContentCurrencyConversionTitle),
                info: String(localizable: .smartBannerContentCurrencyConversionInfo),
                cta: String(localizable: .smartBannerContentCurrencyConversionButton),
                event: .currencyConversionTapped
            )
        default:
            return nil
        }
    }
}

private struct ZappSmartAction {
    let icon: Image
    let title: String
    let info: String
    let cta: String
    let event: SmartBanner.Action
    var isEnabled = true
}
