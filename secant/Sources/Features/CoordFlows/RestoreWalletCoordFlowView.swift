//
//  RestoreWalletCoordFlowView.swift
//  Zashi
//
//  Created by Lukáš Korba on 27-03-2025.
//

import SwiftUI
import ComposableArchitecture

struct RestoreWalletCoordFlowView: View {
    @Environment(\.colorScheme) var colorScheme

    @Perception.Bindable var store: StoreOf<RestoreWalletCoordFlow>

    init(store: StoreOf<RestoreWalletCoordFlow>) {
        self.store = store
    }
    
    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                Group {
                    switch store.landingStep {
                    case .welcome:
                        ZappWelcomeGateView(
                            onGetStarted: {
                                store.send(.landingGetStartedTapped, animation: ZappMotion.content)
                            },
                            onRestoreExisting: {
                                store.send(.importExistingWallet)
                            }
                        )
                    case .walletIntro:
                        ZappWalletIntroView(
                            onBack: {
                                store.send(.landingBackTapped, animation: ZappMotion.content)
                            },
                            onContinue: {
                                store.send(.landingContinueTapped, animation: ZappMotion.content)
                            }
                        )
                    case .walletChoice:
                        ZappWalletChoiceView(
                            onBack: {
                                store.send(.landingBackTapped, animation: ZappMotion.content)
                            },
                            onCreate: {
                                store.send(.createNewWalletTapped)
                            },
                            onRestore: {
                                store.send(.importExistingWallet)
                            }
                        )
                    case .creatingWallet:
                        ZappOnboardingLoadingView(
                            message: String(localizable: .onboardingCreatingWalletMessage),
                            errorMessage: store.walletCreationError == nil
                                ? nil
                                : String(localizable: .onboardingCreatingWalletFailed),
                            errorDetail: store.walletCreationError,
                            onRetry: store.walletCreationError == nil
                                ? nil
                                : { store.send(.createNewWalletRetryTapped) }
                        )
                    }
                }
                .id(store.landingStep)
                .transition(.zappLandingSlide(forward: store.landingForward))
                // Not every landing-step change comes from a button (`creatingWallet` is
                // entered by an effect), so drive the transition off the step itself rather
                // than relying on each send site passing an animation.
                .animation(ZappMotion.content, value: store.landingStep)
                .background(ZappColors.bg.color(colorScheme))
                .zashiSheet(isPresented: $store.isHelpSheetPresented) {
                    helpSheetContent()
                }
                .alert($store.scope(state: \.alert, action: \.alert))
            } destination: { store in
                switch store.case {
                case let .appLockSetup(store):
                    AppLockSetupView(store: store)
                case let .chatUsername(store):
                    ChatUsernameEntryView(store: store)
                case let .done(store):
                    ZappOnboardingDoneView(store: store)
                case let .identityDerivation(store):
                    ZappIdentityDerivationView(store: store)
                case let .keepOpen(store):
                    ZappKeepOpenView(store: store)
                case let .messagingIntro(store):
                    ZappMessagingIntroView(store: store)
                case let .restoreBirthday(store):
                    ZappRestoreBirthdayView(store: store)
                case let .restoreSeedEntry(store):
                    ZappRestoreSeedEntryView(store: store)
                case let .restoring(store):
                    ZappRestoreProgressView(store: store)
                case let .seedBackup(store):
                    ZappOnboardingSeedBackupView(store: store)
                }
            }
        }
    }
    
    @ViewBuilder private func helpSheetContent() -> some View {
        VStack(spacing: 0) {
            Text(localizable: .restoreWalletHelpTitle)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .padding(.top, 24)
                .padding(.bottom, 12)
            
            infoContent(text: String(localizable: .restoreWalletHelpPhrase))
                .padding(.bottom, 12)
            
            infoContent(text: String(localizable: .walletBirthdayHelpDescRecovery))
                .padding(.bottom, 32)
            
            ZashiButton(String(localizable: .restoreInfoGotIt)) {
                store.send(.helpSheetRequested)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
    
    @ViewBuilder private func infoContent(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Asset.Assets.infoCircle.image
                .zImage(size: 20, style: Design.Text.primary)
            
            if let attrText = try? AttributedString(
                markdown: text,
                including: \.zashiApp
            ) {
                ZashiText(withAttributedString: attrText, colorScheme: colorScheme)
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Zapp onboarding landing screens

// Black where Android's screens are Black (`WelcomeGateView.kt`, `SeedRevealScreen`,
// `OnboardingDoneScreen.kt`); the shared `onboardingHero` token stays Bold for the other steps.
private extension ZappTextStyle {
    static let onboardingWordmark = ZappTextStyle(
        weight: .black,
        size: 22,
        lineHeight: 28,
        tracking: -0.5
    )
    static let onboardingWelcomeHero = ZappTextStyle(
        weight: .black,
        size: 54,
        lineHeight: 52,
        tracking: -2.4
    )
    static let onboardingSeedTitle = ZappTextStyle(
        weight: .black,
        size: 26,
        lineHeight: 30,
        tracking: -0.8
    )
    static let onboardingDoneCheck = ZappTextStyle(
        weight: .black,
        size: 88,
        lineHeight: 92,
        tracking: -4
    )
    static let onboardingDoneTitle = ZappTextStyle(
        weight: .black,
        size: 42,
        lineHeight: 44,
        tracking: -1.8
    )
}

// Directional ⅕-width slide + fade for onboarding landing-step changes, mirroring
// Android's `ZappOnboardingFlow` AnimatedContent transitionSpec (forward slides in from
// the right, back-navigation from the left).
private struct ZappLandingSlideModifier: ViewModifier {
    let offset: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: offset)
    }
}

extension AnyTransition {
    // Built during main-actor View `body` evaluation, so reading `UIScreen.main` here is safe.
    @MainActor static func zappLandingSlide(forward: Bool) -> AnyTransition {
        let travel = UIScreen.main.bounds.width / 5
        return .asymmetric(
            insertion: .modifier(
                active: ZappLandingSlideModifier(offset: forward ? travel : -travel),
                identity: ZappLandingSlideModifier(offset: 0)
            )
            .combined(with: .opacity),
            removal: .modifier(
                active: ZappLandingSlideModifier(offset: forward ? -travel : travel),
                identity: ZappLandingSlideModifier(offset: 0)
            )
            .combined(with: .opacity)
        )
    }
}

private struct ZappWelcomeGateView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onGetStarted: () -> Void
    let onRestoreExisting: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 24)

                        HStack(spacing: 12) {
                            Asset.Assets.zappWelcomeLogo.image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .accessibilityHidden(true)

                            Text(verbatim: "Zapp")
                                .zappFont(.onboardingWordmark, style: ZappColors.text)
                        }

                        Spacer().frame(height: 40)

                        Text(localizable: .onboardingWelcomeHeroLine1)
                            .zappFont(.onboardingWelcomeHero, style: ZappColors.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(localizable: .onboardingWelcomeHeroLine2)
                            .zappFont(.onboardingWelcomeHero, style: ZappColors.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.top, 6)

                        Rectangle()
                            .fill(ZappColors.text.color(colorScheme))
                            .frame(width: 36, height: 3)
                            .padding(.top, 24)

                        Text(localizable: .onboardingWelcomeBody)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 300, alignment: .leading)
                            .padding(.top, 20)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .frame(minHeight: proxy.size.height)
                }
            }

            // Share the inset dock used by the other onboarding steps so all four border
            // corners stay inside the safe area, clear of the display's rounded corners.
            ZappOnboardingPrimaryDock {
                VStack(spacing: 8) {
                    ZappButton(title: String(localizable: .onboardingWelcomeGetStarted)) {
                        onGetStarted()
                    }

                    ZappButton(
                        title: String(localizable: .onboardingWelcomeRestore),
                        variant: .ghost
                    ) {
                        onRestoreExisting()
                    }
                    .accessibilityIdentifier(AccessibilityID.Onboarding.restoreWallet)

                    Text(localizable: .onboardingWelcomeTerms)
                        .zappFont(.groupLabel, style: ZappColors.textSubtle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
        }
        .background(ZappColors.bg.color(colorScheme))
        .navigationBarBackButtonHidden(true)
    }
}

private struct ZappWalletIntroView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZappOnboardingProgress(step: 1)
                .padding(.horizontal, 28)
                .padding(.top, 20)

            ScrollView {
                ZStack(alignment: .topTrailing) {
                    ZappOnboardingGhostNumber(number: 1)

                    VStack(alignment: .leading, spacing: 0) {
                        ZappOnboardingEyebrow(text: String(localizable: .onboardingWalletIntroBadge))

                        Text(localizable: .onboardingWalletIntroTitle)
                            .zappFont(.onboardingHero, style: ZappColors.text)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)

                        Text(localizable: .onboardingWalletIntroSubtitle)
                            .zappFont(.onboardingSub, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)

                        VStack(spacing: 0) {
                            ZappOnboardingBullet(
                                title: String(localizable: .onboardingWalletIntroCreateTitle),
                                subtitle: String(localizable: .onboardingWalletIntroCreateSubtitle)
                            )
                            ZappOnboardingBullet(
                                title: String(localizable: .onboardingWalletIntroPhraseTitle),
                                subtitle: String(localizable: .onboardingWalletIntroPhraseSubtitle)
                            )
                        }
                        .padding(.top, 28)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }

            ZappBottomActionBar(onBack: onBack) {
                ZappButton(title: String(localizable: .onboardingContinue), action: onContinue)
            }
        }
        .background(ZappColors.bg.color(colorScheme))
        .zappSwipeBack(action: onBack)
        .navigationBarBackButtonHidden(true)
    }
}

private struct ZappWalletChoiceView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onBack: () -> Void
    let onCreate: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZappOnboardingProgress(step: 1)
                .padding(.horizontal, 28)
                .padding(.top, 20)

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topTrailing) {
                        ZappOnboardingGhostNumber(number: 1)

                        VStack(alignment: .leading, spacing: 0) {
                            ZappOnboardingEyebrow(text: String(localizable: .onboardingWalletChoiceBadge))

                            Text(localizable: .onboardingWalletChoiceTitle)
                                .zappFont(.onboardingHero, style: ZappColors.text)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 14)

                            Text(localizable: .onboardingWalletChoiceSubtitle)
                                .zappFont(.onboardingSub, style: ZappColors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 14)

                            Spacer(minLength: 24)

                            VStack(spacing: 0) {
                                ZappOnboardingAction(
                                    glyph: "✦",
                                    title: String(localizable: .onboardingWalletChoiceCreate),
                                    subtitle: String(localizable: .onboardingWalletChoiceCreateSubtitle),
                                    isHighlighted: true,
                                    action: onCreate
                                )
                                ZappOnboardingAction(
                                    glyph: "⚿",
                                    title: String(localizable: .onboardingWalletChoiceRestore),
                                    subtitle: String(localizable: .onboardingWalletChoiceRestoreSubtitle),
                                    isHighlighted: false,
                                    action: onRestore
                                )
                            }
                            .overlay {
                                Rectangle()
                                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                            }
                            .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }

            ZappBottomActionBar(onBack: onBack)
        }
        .background(ZappColors.bg.color(colorScheme))
        .zappSwipeBack(action: onBack)
        .navigationBarBackButtonHidden(true)
    }
}

private struct ZappMessagingIntroView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<OnboardingMessagingIntro>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappOnboardingProgress(step: 2)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                ScrollView {
                    ZStack(alignment: .topTrailing) {
                        ZappOnboardingGhostNumber(number: 2)

                        VStack(alignment: .leading, spacing: 0) {
                            ZappOnboardingEyebrow(text: String(localizable: .onboardingMsgIntroBadge))

                            Text(localizable: .onboardingMsgIntroTitle)
                                .zappFont(.onboardingHero, style: ZappColors.text)
                                .lineLimit(3)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 14)

                            Text(localizable: .onboardingMsgIntroSubtitle)
                                .zappFont(.onboardingSub, style: ZappColors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 16)

                            VStack(spacing: 0) {
                                ZappOnboardingBullet(
                                    title: String(localizable: .onboardingMsgIntroUsernameTitle),
                                    subtitle: String(localizable: .onboardingMsgIntroUsernameSubtitle)
                                )
                                ZappOnboardingBullet(
                                    title: String(localizable: .onboardingMsgIntroPhraseTitle),
                                    subtitle: String(localizable: .onboardingMsgIntroPhraseSubtitle)
                                )
                            }
                            .padding(.top, 28)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }

                // No back button: the wallet is already committed at this point (Android's
                // MessagingPhaseIntro renders with showBack = false).
                ZappOnboardingPrimaryDock {
                    ZappButton(title: String(localizable: .onboardingContinue)) {
                        store.send(.continueTapped)
                    }
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden(true)
        }
    }
}

private struct ZappOnboardingDoneView: View {
    /// Android's `OnboardingDoneScreen` staged entrance: check, title, rule, subtitle, one every
    /// 90 ms, the check scaling up from 0.6 and the rest sliding up a quarter of their height.
    private enum Constants {
        static let stageCount = 4
        static let stageDelay: Duration = .milliseconds(90)
        static let checkInitialScale: CGFloat = 0.6
        static let slideOffset: CGFloat = 12
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage = 0

    @Perception.Bindable var store: StoreOf<OnboardingDone>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Spacer()

                    Text(verbatim: "✓")
                        .zappFont(.onboardingDoneCheck, style: ZappColors.accent)
                        .scaleEffect(stage >= 1 ? 1 : Constants.checkInitialScale)
                        .opacity(stage >= 1 ? 1 : 0)

                    Text(localizable: .onboardingDoneTitle)
                        .zappFont(.onboardingDoneTitle, style: ZappColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .stagedEntrance(isVisible: stage >= 2, offset: Constants.slideOffset)
                        .padding(.top, 18)

                    Rectangle()
                        .fill(ZappColors.text.color(colorScheme))
                        .frame(width: 36, height: 3)
                        .stagedEntrance(isVisible: stage >= 3, offset: Constants.slideOffset)
                        .padding(.top, 20)

                    Text(
                        store.mode == .pin
                            ? String(localizable: .onboardingDoneSubtitlePin)
                            : String(localizable: .onboardingDoneSubtitleBio)
                    )
                    .zappFont(.onboardingSub, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .stagedEntrance(isVisible: stage >= 4, offset: Constants.slideOffset)
                    .padding(.top, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)

                ZappOnboardingPrimaryDock {
                    ZappButton(title: String(localizable: .onboardingDoneEnterCta)) {
                        store.send(.enterTapped)
                    }
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden(true)
            .task {
                ZappHaptics.success()
                guard !reduceMotion else {
                    stage = Constants.stageCount
                    return
                }
                while stage < Constants.stageCount {
                    withAnimation(ZappMotion.content) { stage += 1 }
                    try? await Task.sleep(for: Constants.stageDelay)
                }
            }
        }
    }
}

private extension View {
    func stagedEntrance(isVisible: Bool, offset: CGFloat) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : offset)
    }
}

private struct ZappIdentityDerivationView: View {
    @Perception.Bindable var store: StoreOf<OnboardingIdentityDerivation>

    var body: some View {
        WithPerceptionTracking {
            ZappOnboardingLoadingView(
                message: String(localizable: .onboardingIdentityDerivingMessage),
                errorMessage: store.errorCode == nil
                    ? nil
                    : String(localizable: .onboardingIdentityDerivingFailed),
                errorDetail: store.errorCode,
                onRetry: store.errorCode == nil
                    ? nil
                    : { store.send(.retryTapped) }
            )
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }
}

private struct ZappOnboardingSeedBackupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Perception.Bindable var store: StoreOf<OnboardingSeedBackup>

    private let wordCount = 24

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappOnboardingProgress(step: 1)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(
                            store.kind == .confirm
                                ? String(localizable: .restoreFlowConfirmTitle)
                                : String(localizable: .onboardingSeedTitle)
                        )
                        .zappFont(.onboardingSeedTitle, style: ZappColors.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(
                            store.kind == .confirm
                                ? String(localizable: .restoreFlowConfirmSubtitle)
                                : String(localizable: .onboardingSeedSubtitle)
                        )
                        .zappFont(.onboardingSub, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)

                        seedGrid
                            .padding(.top, 20)

                        if store.isBlockedByScreenCapture {
                            Text(localizable: .onboardingSeedScreenRecording)
                                .zappFont(.caption, style: ZappColors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                        }

                        confirmation
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }

                ZappOnboardingPrimaryDock {
                    ZappButton(
                        title: String(localizable: .onboardingSeedSavedButton),
                        isEnabled: store.isRevealed && store.isConfirmed
                    ) {
                        store.send(.continueTapped)
                    }
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden(true)
            .privacySensitive()
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                store.send(.hideSensitiveContent)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                store.send(.hideSensitiveContent)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                if UIScreen.main.isCaptured {
                    store.send(.hideSensitiveContent)
                }
            }
            .onDisappear { store.send(.hideSensitiveContent) }
        }
    }

    private var seedGrid: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            HStack(spacing: 6) {
                                Text(String(format: "%02d", index + 1))
                                    .zappFont(.groupLabel, style: ZappColors.textSubtle)
                                    .frame(width: 18, alignment: .leading)

                                Text(word(at: index))
                                    .zappFont(.rowSubtitle, style: ZappColors.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .accessibilityLabel(
                                        store.isRevealed
                                            ? "\(index + 1). \(word(at: index))"
                                            : String(localizable: .onboardingSeedHiddenWordAccessibility)
                                    )
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                (row.isMultiple(of: 2) ? ZappColors.bg : ZappColors.surfaceAlt)
                                    .color(colorScheme)
                            )
                        }
                    }
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }
            .blur(radius: store.isRevealed ? 0 : 14)
            .animation(ZappMotion.reveal, value: store.isRevealed)

            if !store.isRevealed {
                Button {
                    store.send(.revealTapped, animation: ZappMotion.reveal)
                } label: {
                    VStack(spacing: 8) {
                        if store.isLoading {
                            ProgressView()
                                .tint(ZappColors.onAccent.color(colorScheme))
                                .frame(width: 44, height: 44)
                                .background(ZappColors.text.color(colorScheme))
                        } else {
                            Asset.Assets.eyeOn.image
                                .zImage(size: 18, style: ZappColors.bg)
                                .frame(width: 44, height: 44)
                                .background(ZappColors.text.color(colorScheme))
                        }

                        Text(
                            store.errorMessage == nil
                                ? String(localizable: .onboardingSeedTapToReveal)
                                : String(localizable: .onboardingSeedRevealRetry)
                        )
                        .zappFont(.buttonSmall, style: ZappColors.text)
                    }
                }
                .buttonStyle(.zappPress)
                .disabled(store.isLoading)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var confirmation: some View {
        Button {
            store.send(.confirmationTapped, animation: ZappMotion.state)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Rectangle()
                        .fill(store.isConfirmed ? ZappColors.accent.color(colorScheme) : .clear)
                    Rectangle()
                        .strokeBorder(
                            (store.isConfirmed ? ZappColors.accent : ZappColors.borderStrong)
                                .color(colorScheme),
                            lineWidth: 2
                        )
                    if store.isConfirmed {
                        Text("✓")
                            .zappFont(.buttonSmall, style: ZappColors.onAccent)
                    }
                }
                .frame(width: 20, height: 20)

                Text(localizable: .onboardingSeedConfirmation)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.zappPress)
        .disabled(!store.isRevealed)
        .opacity(store.isRevealed ? 1 : 0.45)
    }

    private func word(at index: Int) -> String {
        guard store.isRevealed, index < store.words.count else {
            return "•••••"
        }
        return store.words[index].data
    }
}

private struct ZappOnboardingBullet: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .zappFont(.rowTitle, style: ZappColors.text)
                Text(subtitle)
                    .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)
        }
    }
}

private struct ZappOnboardingAction: View {
    @Environment(\.colorScheme) private var colorScheme

    let glyph: String
    let title: String
    let subtitle: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(glyph)
                    .zappFont(.sectionTitle, style: ZappColors.accentText)
                    .frame(width: 40, height: 40)
                    .background(ZappColors.accentSoft.color(colorScheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .zappFont(.rowTitle, style: ZappColors.text)
                    Text(subtitle)
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("→")
                    .zappFont(.sectionTitle, style: ZappColors.text)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isHighlighted ? ZappColors.accentSoft : ZappColors.surface)
                    .color(colorScheme)
            )
        }
        .buttonStyle(.zappPress)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)
        }
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

#Preview {
    NavigationView {
        RestoreWalletCoordFlowView(store: RestoreWalletCoordFlow.placeholder)
    }
}

// MARK: - Placeholders

extension RestoreWalletCoordFlow.State {
    static var initial: RestoreWalletCoordFlow.State { RestoreWalletCoordFlow.State() }
}

extension RestoreWalletCoordFlow {
    @MainActor static let placeholder = StoreOf<RestoreWalletCoordFlow>(
        initialState: .initial
    ) {
        RestoreWalletCoordFlow()
    }
}
