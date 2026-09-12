// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct ReputationView: View {
    @Perception.Bindable var store: StoreOf<Reputation>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .reputationTitle)) {
                    ZappInfoButton(
                        accessibilityLabel: String(localizable: .reputationInfoContentDescription)
                    ) {
                        store.send(.infoTapped)
                    }
                }

                ScrollView {
                    body(for: store.content)
                        .padding(.horizontal, ReputationLayout.gutter)
                        .padding(.vertical, ReputationLayout.verticalPadding)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                    if let action = store.primaryAction {
                        ZappButton(title: title(for: action)) { store.send(tap(for: action)) }
                    }
                }
            }
            .applyScreenBackground()
            .task { await store.send(.onAppear).finish() }
            .onDisappear { store.send(.onDisappear) }
            .sheet(isPresented: infoBinding) {
                ReputationInfoSheet { store.send(.infoDismissed) }
            }
        }
    }

    private var infoBinding: Binding<Bool> {
        Binding(get: { store.isInfoPresented }, set: { if !$0 { store.send(.infoDismissed) } })
    }

    @ViewBuilder
    private func body(for content: Reputation.State.Content) -> some View {
        switch content {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, ReputationLayout.loadingTopPadding)

        case .unreadable:
            VStack(alignment: .leading, spacing: ReputationLayout.sectionGap) {
                Text(String(localizable: .reputationUnreadableTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                ReputationNotice(text: String(localizable: .reputationUnreadableBody))
                raiseLimitAction
            }

        case .blocked:
            VStack(alignment: .leading, spacing: ReputationLayout.sectionGap) {
                Text(String(localizable: .reputationBlacklistedTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                ReputationNotice(text: String(localizable: .reputationBlacklistedBody))
            }

        case let .ready(summary):
            VStack(alignment: .leading, spacing: ReputationLayout.sectionGap) {
                buyLimitCard(summary)

                if !summary.verified.isEmpty {
                    ZappSettingsGroup(title: String(localizable: .reputationVerifiedGroup)) {
                        ForEach(Array(summary.verified.enumerated()), id: \.element.id) { index, platform in
                            if index > 0 { ZappRowDivider() }
                            verifiedRow(platform)
                        }
                    }
                }

                raiseLimitAction
            }
        }
    }

    /// The figure the user came for, given the full width instead of the right-hand column of a
    /// table. The locked state is a sentence, not a value, and that is the whole reason this is a
    /// card: as a row it clipped to "Locked until you verify one acc…".
    @ViewBuilder
    private func buyLimitCard(_ summary: ReputationSummaryModel) -> some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: 0) {
                ZappSectionLabel(text: String(localizable: .reputationBuyLimit))

                Text(store.buyLimitText ?? "")
                    .zappFont(.display, style: summary.canBuy ? ZappColors.text : ZappColors.textMuted)
                    .padding(.top, ReputationLayout.heroLabelGap)

                Text(store.buyLimitCaption ?? "")
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ReputationLayout.heroCaptionGap)

                ZappRowDivider()
                    .padding(.vertical, ReputationLayout.heroDividerGap)

                ZappSummaryRow(
                    label: String(localizable: .reputationPointsRow),
                    value: summary.points
                )
            }
        }
    }

    /// No chevron and no tap: this group reports what the user has already earned. Everything that
    /// can still be done about it is one button away, so the two never compete.
    private func verifiedRow(_ platform: ReputationPlatformModel) -> some View {
        ZappRow(
            title: platform.name,
            icon: Asset.Assets.check.image,
            iconTint: .success,
            iconBackground: .successSoft
        ) {
            Text(String(localizable: .reputationRpAmount(platform.awardPoints)))
                .zappFont(.rowSubtitle, style: ZappColors.textMuted)
        }
    }

    /// Always present when raising the limit is worth anything, always secondary. The bottom bar
    /// carries what the user wants next; this carries what they can do about it.
    @ViewBuilder
    private var raiseLimitAction: some View {
        if store.isRaiseLimitVisible {
            ZappCompactButton(title: String(localizable: .reputationRaiseLimit)) {
                store.send(.raiseLimitTapped)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func title(for action: Reputation.State.PrimaryAction) -> String {
        switch action {
        case .buy: return String(localizable: .reputationBuy)
        case .verifyToBuy: return String(localizable: .reputationVerifyToBuy)
        case .retry: return String(localizable: .reputationRetry)
        }
    }

    private func tap(for action: Reputation.State.PrimaryAction) -> Reputation.Action {
        switch action {
        case .buy: return .buyTapped
        case .verifyToBuy: return .raiseLimitTapped
        case .retry: return .retryTapped
        }
    }
}

/// Where the mechanism is explained, so the screen itself can stay bare. Buying is a trade with a
/// stranger and the cap is the exchange's, not ours — both facts land here rather than as body
/// copy no one reads twice.
struct ReputationInfoSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ReputationLayout.sheetGap) {
            Text(String(localizable: .reputationInfoTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)
            Text(String(localizable: .reputationInfoTrade))
                .zappFont(.body, style: ZappColors.text)
            Text(String(localizable: .reputationInfoCap))
                .zappFont(.body, style: ZappColors.text)
            Text(String(localizable: .reputationInfoPrivacy))
                .zappFont(.caption, style: ZappColors.textMuted)
            Text(String(localizable: .reputationInfoSource))
                .zappFont(.caption, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zappInfoSheet(onDismiss: onDismiss)
    }
}

/// The muted block both reputation screens end on. Byte-identical in each of them before this,
/// which is one edit away from two screens that quietly stop matching.
struct ReputationNotice: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    var body: some View {
        Text(text)
            .zappFont(.body, style: ZappColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReputationLayout.noticePadding)
            .background(ZappColors.surfaceAlt.color(colorScheme))
    }
}

/// The measurements the two reputation screens share. Anything that lands on a `Design.Spacing`
/// token uses the token; the off-scale ones stay literal here rather than being rounded onto the
/// scale, which would move a layout to tidy a constant.
enum ReputationLayout {
    static let gutter: CGFloat = 18
    static let verticalPadding = Design.Spacing._xl
    static let sectionGap = Design.Spacing._xl
    static let noticePadding = Design.Spacing._lg
    static let rowTrailingGap = Design.Spacing._sm
    static let sheetGap = Design.Spacing._lg
    static let loadingTopPadding = Design.Spacing._6xl
    static let heroLabelGap: CGFloat = 10
    static let heroCaptionGap: CGFloat = 6
    static let heroDividerGap = Design.Spacing._xl
}

#Preview {
    ReputationView(
        store: Store(initialState: .initial(currencyCode: "INR")) { Reputation() }
    )
    .applyScreenBackground()
}
