//
//  ZappRestoreSteps.swift
//  Zapp
//
//  The two small restore steps: RESTORING (Android's `RestoreInProgressScreen`) and KEEP_OPEN
//  (`KeepZappOpenScreen`), both in view/RestoreFlowViews.kt.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct ZappRestoreProgress {
    @ObservableState
    struct State: Equatable {
        var errorMessage: String?

        static let initial = State()
    }

    enum Action: Equatable {
        /// The coordinator reruns the restore it is holding.
        case retryTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

struct ZappRestoreProgressView: View {
    @Perception.Bindable var store: StoreOf<ZappRestoreProgress>

    var body: some View {
        WithPerceptionTracking {
            ZappOnboardingLoadingView(
                message: String(localizable: .restoreFlowLoadingMessage),
                errorMessage: store.errorMessage,
                retryHint: String(localizable: .restoreFlowLoadingError),
                noRetryHint: String(localizable: .restoreFlowLoadingErrorNoRetry),
                onRetry: store.errorMessage == nil ? nil : { store.send(.retryTapped) }
            )
        }
    }
}

@Reducer
struct ZappKeepOpen {
    @ObservableState
    struct State: Equatable {
        /// Off by default, as Android's `ZappRestoreFlowVM.keepScreenOn`.
        var keepsScreenOn = false

        static let initial = State()
    }

    enum Action: Equatable {
        case enterTapped
        case keepScreenOnToggled
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .keepScreenOnToggled:
                state.keepsScreenOn.toggle()
                return .none

            case .enterTapped:
                // The coordinator finishes onboarding on this.
                return .none
            }
        }
    }
}

struct ZappKeepOpenView: View {
    private enum Constants {
        /// The restore flow's last step sits in Part 3, after the app lock.
        static let part = 3
        static let checkboxSize: CGFloat = 20
        static let checkboxTarget: CGFloat = 44
    }

    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ZappKeepOpen>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappOnboardingProgress(step: Constants.part)
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.progressTopPadding)

                ScrollView {
                    ZStack(alignment: .topTrailing) {
                        ZappOnboardingGhostNumber(number: Constants.part)

                        VStack(alignment: .leading, spacing: 0) {
                            ZappRestoreHeading(
                                badge: String(localizable: .restoreFlowKeepOpenBadge),
                                title: String(localizable: .restoreFlowKeepOpenTitle),
                                subtitle: String(localizable: .restoreFlowKeepOpenSubtitle)
                            )

                            VStack(spacing: 0) {
                                bullet(String(localizable: .restoreFlowKeepOpenBullet1), isFirst: true)
                                bullet(String(localizable: .restoreFlowKeepOpenBullet2), isFirst: false)
                            }
                            .padding(.top, 28)

                            checkbox
                                .padding(.top, 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.contentTopPadding)
                    .padding(.bottom, 16)
                }

                // No back: the wallet, its identity and the app lock are all committed by now.
                ZappOnboardingPrimaryDock {
                    ZappButton(title: String(localizable: .restoreFlowKeepOpenCta)) {
                        store.send(.enterTapped)
                    }
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden(true)
        }
    }

    private func bullet(_ text: String, isFirst: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: 3)

            Text(text)
                .zappFont(.rowTitle, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)
        }
    }

    private var checkbox: some View {
        Button {
            store.send(.keepScreenOnToggled, animation: ZappMotion.state)
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    Rectangle()
                        .fill((store.keepsScreenOn ? ZappColors.accent : ZappColors.bg).color(colorScheme))
                    Rectangle()
                        .strokeBorder(
                            (store.keepsScreenOn ? ZappColors.accent : ZappColors.borderStrong).color(colorScheme),
                            lineWidth: 2
                        )
                    if store.keepsScreenOn {
                        Text(verbatim: "✓")
                            .zappFont(.buttonSmall, style: ZappColors.onAccent)
                    }
                }
                .frame(width: Constants.checkboxSize, height: Constants.checkboxSize)
                .frame(width: Constants.checkboxTarget, height: Constants.checkboxTarget)

                Text(localizable: .restoreFlowKeepOpenCheckbox)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.zappPress)
        .accessibilityAddTraits(store.keepsScreenOn ? .isSelected : [])
    }
}
