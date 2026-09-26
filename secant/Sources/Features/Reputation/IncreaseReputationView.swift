// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct IncreaseReputationView: View {
    @Environment(\.openURL) private var openURL

    @Perception.Bindable var store: StoreOf<IncreaseReputation>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .increaseReputationTitle)) {
                    ZappInfoButton(
                        accessibilityLabel: String(localizable: .increaseReputationInfoContentDescription)
                    ) {
                        store.send(.infoTapped)
                    }
                }

                ScrollView {
                    Group {
                        if store.requiresResumeConfirmation {
                            resumeConfirmation
                        } else if let run = store.run {
                            runBody(run)
                        } else if store.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, ReputationLayout.loadingTopPadding)
                        } else {
                            listBody
                        }
                    }
                    .padding(.horizontal, ReputationLayout.gutter)
                    .padding(.vertical, ReputationLayout.verticalPadding)
                }

                bottomDock
            }
            .applyScreenBackground()
            .task { await store.send(.onAppear).finish() }
            .onDisappear { store.send(.onDisappear) }
            .sheet(isPresented: infoBinding) {
                IncreaseReputationInfoSheet { store.send(.infoDismissed) }
            }
        }
    }

    private var infoBinding: Binding<Bool> {
        Binding(get: { store.isInfoPresented }, set: { if !$0 { store.send(.infoDismissed) } })
    }

    private var resumeConfirmation: some View {
        VStack(alignment: .leading, spacing: ReputationLayout.sectionGap) {
            Text(String(localizable: .increaseReputationResumeTitle(store.resumePlatformID ?? "")))
                .zappFont(.sectionTitle, style: ZappColors.text)
            ReputationNotice(text: String(localizable: .increaseReputationResumeBody))
            Text(String(localizable: .reputationInfoPrivacy))
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listBody: some View {
        VStack(alignment: .leading, spacing: ReputationLayout.sectionGap) {
            Text(String(localizable: .increaseReputationIntro))
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let message = store.errorMessage {
                Text(message)
                    .zappFont(.body, style: ZappColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.platforms.isEmpty {
                ZappSettingsGroup(title: String(localizable: .increaseReputationGroup)) {
                    ForEach(Array(store.platforms.enumerated()), id: \.element.id) { index, platform in
                        if index > 0 { ZappRowDivider() }
                        platformRow(platform)
                    }
                }
            }

            identityGroup

            if let liveness = store.liveness {
                ZappSettingsGroup(
                    title: String(localizable: .increaseReputationLivenessGroup),
                    footer: String(localizable: .increaseReputationLivenessFooter)
                ) {
                    selfieRow(liveness)
                }
            }
        }
    }

    /// The reward is dollars rather than RP: the selfie unlocks a limit, not points.
    private func selfieRow(_ liveness: LivenessStandingModel) -> some View {
        ZappRow(
            title: String(localizable: .increaseReputationLivenessRow),
            subtitle: String(localizable: .increaseReputationLivenessSubtitle),
            titleColor: liveness.isVerified ? .textMuted : .text,
            trailing: {
                if liveness.isVerified {
                    verifiedTrailing(String(localizable: .reputationAmountUsd(ReputationCopy.usd(liveness.limitMicros))))
                } else {
                    Text(String(localizable: .increaseReputationLivenessReward(ReputationCopy.usd(liveness.tierCapMicros))))
                        .zappFont(.rowSubtitle, style: ZappColors.accentText)
                }
            },
            action: liveness.isVerified ? nil : { store.send(.selfieTapped) }
        )
    }

    /// Verified rows stay listed and inert: hiding one reads as a bug, and nothing else in the app
    /// tells the user that account is already spent.
    private func platformRow(_ platform: ReputationPlatformModel) -> some View {
        ZappRow(
            title: platform.name,
            subtitle: platform.requiresMatureAccount && !platform.isVerified
                ? String(localizable: .increaseReputationAgeRequirement)
                : nil,
            titleColor: platform.isVerified ? .textMuted : .text,
            trailing: { platformTrailing(platform) },
            action: platform.isVerified ? nil : { store.send(.platformTapped(platform.id)) }
        )
    }

    @ViewBuilder
    private func platformTrailing(_ platform: ReputationPlatformModel) -> some View {
        if platform.isVerified {
            verifiedTrailing(String(localizable: .reputationRpAmount(platform.awardPoints)))
        } else {
            // Two lines, right-aligned: what the account is worth in points, and what that is
            // worth in dollars of limit. The second is the one people actually decide on.
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(localizable: .increaseReputationReward(platform.awardPoints)))
                    .zappFont(.rowSubtitle, style: ZappColors.accentText)

                if let gain = platform.limitGainMicros {
                    Text(String(localizable: .increaseReputationLimitGain(ReputationCopy.usd(gain))))
                        .zappFont(.caption, style: ZappColors.textMuted)
                }
            }
        }
    }

    /// Says the state, not just the reward: a bare "50 RP" beside a tick reads as an offer rather
    /// than as points already banked.
    private func verifiedTrailing(_ reward: String) -> some View {
        HStack(spacing: ReputationLayout.rowTrailingGap) {
            Asset.Assets.check.image
                .zImage(size: IncreaseReputationLayout.checkSize, style: ZappColors.success)
            Text(String(localizable: .increaseReputationVerifiedReward(reward)))
                .zappFont(.rowSubtitle, style: ZappColors.success)
        }
    }

    @ViewBuilder
    private func runBody(_ run: IncreaseReputation.State.Run) -> some View {
        VStack(alignment: .leading, spacing: ReputationLayout.sectionGap) {
            if run.stage == .done {
                ZappSuccessHeader(
                    title: run.kind == .selfie
                        ? String(localizable: .increaseReputationLivenessDone)
                        : String(localizable: .increaseReputationDone(run.name)),
                    subtitle: run.newBuyLimitMicros.map {
                        String(localizable: .increaseReputationNewLimit(ReputationCopy.usd($0)))
                    } ?? ""
                )

                if let points = run.newPoints {
                    Text(String(localizable: .reputationRpAmount(points)))
                        .zappFont(.display, style: ZappColors.text)
                }
            } else {
                Text(message(for: run))
                    .zappFont(.body, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                ZappOfframpStepList(items: store.steps)

                // ☠ iOS suspends the poller the moment the app backgrounds, and the session's ten
                // minutes keep running. Saying so is what stops a spent budget reading as a bug.
                if run.stage == .verifying {
                    ReputationNotice(text: run.isSelfie
                        ? String(localizable: .increaseReputationLivenessWaitingHelp)
                        : String(localizable: .increaseReputationWaitingHelp))
                }
            }

            if let message = run.errorMessage {
                Text(message)
                    .zappFont(.body, style: ZappColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Cancelling lives in the body, never in the dock: the dock carries the way forward.
            if run.stage == .ready || run.stage == .verifying {
                ZappCompactButton(title: String(localizable: .increaseReputationCancel)) {
                    store.send(.cancelRunTapped)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var bottomDock: some View {
        ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
            if store.requiresResumeConfirmation {
                ZappButton(title: String(localizable: .increaseReputationResumeConfirm)) { store.send(.resumeConfirmed) }
            } else if store.run != nil || store.canRetryLoad {
                primaryButton
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let run = store.run {
            switch run.stage {
            case .preparing, .verifying:
                ZappButton(title: openTitle(for: run), isEnabled: false) { }
            case .ready:
                ZappButton(title: openTitle(for: run)) { openVerifier(run) }
            case .submitting:
                ZappButton(title: String(localizable: .increaseReputationSavingAction), isEnabled: false) { }
            case .done:
                ZappButton(title: String(localizable: .increaseReputationFinish)) { store.send(.doneTapped) }
            case .failed:
                ZappButton(title: String(localizable: .reputationRetry)) { store.send(.retryRunTapped) }
            }
        } else {
            ZappButton(title: String(localizable: .reputationRetry)) { store.send(.retryLoadTapped) }
        }
    }

    private func openTitle(for run: IncreaseReputation.State.Run) -> String {
        run.isSelfie
            ? String(localizable: .increaseReputationLivenessOpen)
            : String(localizable: .increaseReputationOpen)
    }

    /// The one thing only the view can do. iOS resolves the share link to the Reclaim Verifier when
    /// it is installed and to Safari otherwise, which is the same deferred deep link Android gets —
    /// so one open is enough, and there is no `market://` equivalent to fall back to. Whether it
    /// actually opened is what `.verifierOpened` needs.
    private func openVerifier(_ run: IncreaseReputation.State.Run) {
        guard let raw = run.launchURL, let url = URL(string: raw) else {
            store.send(.verifierOpened(runID: run.id, accepted: false))
            return
        }
        openURL(url) { accepted in
            store.send(.verifierOpened(runID: run.id, accepted: accepted))
        }
    }

    private func message(for run: IncreaseReputation.State.Run) -> String {
        if let message = passportMessage(for: run) { return message }
        switch (run.stage, run.isSelfie) {
        case (.preparing, _): return String(localizable: .increaseReputationPreparing)
        case (.ready, false): return String(localizable: .increaseReputationReady(run.name))
        case (.ready, true): return String(localizable: .increaseReputationLivenessReady)
        case (.verifying, false): return String(localizable: .increaseReputationWaiting)
        case (.verifying, true): return String(localizable: .increaseReputationLivenessWaiting)
        case (.submitting, _): return String(localizable: .increaseReputationSaving)
        case (.done, false): return String(localizable: .increaseReputationDone(run.name))
        case (.done, true): return String(localizable: .increaseReputationLivenessDone)
        case (.failed, _): return String(localizable: .increaseReputationFailed)
        }
    }
}

private extension IncreaseReputationView {
    @ViewBuilder var identityGroup: some View {
        if !store.identityChecks.isEmpty {
            ZappSettingsGroup(title: String(localizable: .increaseReputationIdentityGroup)) {
                ForEach(Array(store.identityChecks.enumerated()), id: \.element.id) { index, check in
                    if index > 0 { ZappRowDivider() }
                    ZappRow(
                        title: check.id == IdentityCheckModel.passport.rawValue
                            ? String(localizable: .increaseReputationPassportRow)
                            : String(localizable: .increaseReputationLivenessRow),
                        titleColor: check.isVerified ? .textMuted : .text,
                        trailing: { platformTrailing(check) },
                        action: check.isVerified ? nil : {
                            if let kind = IdentityCheckModel(rawValue: check.id) { store.send(.identityTapped(kind)) }
                        }
                    )
                }
            }
        }
    }

    func passportMessage(for run: IncreaseReputation.State.Run) -> String? {
        guard run.kind == .passport else { return nil }
        switch run.stage {
        case .ready, .verifying: return String(localizable: .increaseReputationPassportWaiting)
        case .done: return String(localizable: .increaseReputationDone(run.name))
        default: return nil
        }
    }
}

/// The four things a user needs to know before spending five minutes in another app: what Reclaim
/// is, that we pay the fee, that older accounts only, and that a verification is spent once and for
/// good — including against a wallet recovered from a new seed.
struct IncreaseReputationInfoSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let onDismiss: () -> Void

    private static let steps = [
        String(localizable: .increaseReputationInfoStepPick),
        String(localizable: .increaseReputationInfoStepOpen),
        String(localizable: .increaseReputationInfoStepSignIn),
        String(localizable: .increaseReputationInfoStepProof)
    ]

    private static let notes = [
        String(localizable: .increaseReputationInfoGas),
        String(localizable: .increaseReputationInfoTime),
        String(localizable: .increaseReputationInfoAge),
        String(localizable: .increaseReputationInfoOnce)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ReputationLayout.sheetGap) {
            Text(String(localizable: .increaseReputationInfoTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: ReputationLayout.sheetGap) {
                    Text("\(index + 1)")
                        .zappFont(.caption, style: ZappColors.accentText)
                        .frame(
                            width: IncreaseReputationLayout.stepBadge,
                            height: IncreaseReputationLayout.stepBadge
                        )
                        .background(ZappColors.accentSoft.color(colorScheme))

                    Text(step)
                        .zappFont(.body, style: ZappColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(Self.notes, id: \.self) { note in
                Text(note)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zappInfoSheet(onDismiss: onDismiss)
    }
}

private enum IncreaseReputationLayout {
    static let checkSize: CGFloat = 18
    static let stepBadge: CGFloat = 20
}

#Preview {
    IncreaseReputationView(
        store: Store(initialState: .initial(currencyCode: "INR")) { IncreaseReputation() }
    )
    .applyScreenBackground()
}
