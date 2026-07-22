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
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .background(ZappColors.bg.color(colorScheme))
                .zashiSheet(isPresented: $store.isHelpSheetPresented) {
                    helpSheetContent()
                }
                .zashiSheet(isPresented: $store.isTorSheetPresented) {
                    torSheetContent()
                }
                .alert($store.scope(state: \.alert, action: \.alert))
            } destination: { store in
                switch store.case {
                case let .chatUsername(store):
                    ChatUsernameEntryView(store: store)
                case let .estimateBirthdaysDate(store):
                    WalletBirthdayEstimateDateView(store: store)
                case let .estimatedBirthday(store):
                    WalletBirthdayEstimatedHeightView(store: store)
                case let .identityDerivation(store):
                    ZappIdentityDerivationView(store: store)
                case let .recoverySeedPhraseEntry(store):
                    RecoverySeedPhraseEntryView(store: store)
                case let .restoreInfo(store):
                    RestoreInfoView(store: store)
                case let .seedBackup(store):
                    ZappOnboardingSeedBackupView(store: store)
                case let .walletBirthday(store):
                    WalletBirthdayView(store: store)
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
    
    @ViewBuilder private func torSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Asset.Assets.infoOutline.image
                .zImage(size: 20, style: Design.Utility.Gray._500)
                .background {
                    Circle()
                        .fill(Design.Utility.Gray._100.color(colorScheme))
                        .frame(width: 44, height: 44)
                }
                .padding(.top, 48)
                .padding(.leading, 12)
            
            Text(localizable: .torSettingsSheetTitle)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .padding(.top, 24)
                .padding(.bottom, 12)
            
            Text(localizable: .torSettingsSheetMsg)
                .zFont(size: 14, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(.bottom, Design.Spacing._3xl)
            
            DescriptiveToggle(
                isOn: $store.isTorOn,
                title: String(localizable: .torSettingsSheetTitle),
                desc: String(localizable: .torSettingsSheetDesc)
            )
            .padding(.bottom, 32)
            
            ZashiButton(String(localizable: .generalCancel), type: .tertiary) {
                store.send(.restoreCancelTapped)
            }
            .padding(.bottom, Design.Spacing._lg)
            
            ZashiButton(String(localizable: .importWalletButtonRestoreWallet)) {
                store.send(.resolveRestoreRequested)
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

private extension ZappTextStyle {
    static let onboardingWelcomeHero = ZappTextStyle(
        weight: .bold,
        size: 54,
        lineHeight: 52,
        tracking: -2.4
    )
    static let onboardingHero = ZappTextStyle(
        weight: .bold,
        size: 42,
        lineHeight: 44,
        tracking: -1.4
    )
    static let onboardingGhost = ZappTextStyle(
        weight: .bold,
        size: 130,
        lineHeight: 130,
        tracking: -5
    )
    static let onboardingSub = ZappTextStyle(
        weight: .regular,
        size: 13,
        lineHeight: 22
    )
    static let onboardingSeedTitle = ZappTextStyle(
        weight: .bold,
        size: 26,
        lineHeight: 30,
        tracking: -0.8
    )
    static let onboardingGreeting = ZappTextStyle(
        weight: .bold,
        size: 112,
        lineHeight: 104,
        tracking: -5
    )
}

private struct ZappWelcomeGateView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onGetStarted: () -> Void
    let onRestoreExisting: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                HStack(spacing: 12) {
                    Text("Z")
                        .zappFont(.displaySecondary, style: ZappColors.onAccent)
                        .frame(width: 40, height: 40)
                        .background(ZappColors.accent.color(colorScheme))

                    Text("Zapp")
                        .zappFont(.screenTitle, style: ZappColors.text)
                }

                Spacer().frame(height: 40)

                Text(localizable: .onboardingWelcomeHeroLine1)
                    .zappFont(.onboardingWelcomeHero, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizable: .onboardingWelcomeHeroLine2)
                    .zappFont(.onboardingWelcomeHero, style: ZappColors.accent)
                    .fixedSize(horizontal: false, vertical: true)
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
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background(ZappColors.surface.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.text.color(colorScheme), lineWidth: 1)
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

            ZStack(alignment: .topTrailing) {
                ZappOnboardingGhostNumber(number: 1)

                VStack(alignment: .leading, spacing: 0) {
                    ZappOnboardingEyebrow(text: String(localizable: .onboardingWalletChoiceBadge))

                    Text(localizable: .onboardingWalletChoiceTitle)
                        .zappFont(.onboardingHero, style: ZappColors.text)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            ZappBottomActionBar(onBack: onBack)
        }
        .background(ZappColors.bg.color(colorScheme))
        .zappSwipeBack(action: onBack)
        .navigationBarBackButtonHidden(true)
    }
}

private struct ZappOnboardingLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var pulse = false

    let message: String
    let errorMessage: String?
    let errorDetail: String?
    let onRetry: (() -> Void)?

    var body: some View {
        ZStack {
            ZappLoadingWave(heightFraction: pulse ? 0.48 : 0.30)
                .fill(Color.white.opacity(0.10))
            ZappLoadingWave(heightFraction: pulse ? 0.20 : 0.36)
                .fill(Color.white.opacity(0.16))

            VStack(spacing: 0) {
                Text(localizable: .onboardingLoadingGreeting)
                    .zappFont(.onboardingGreeting, color: .white)

                Rectangle()
                    .fill(ZappColors.text.color(colorScheme))
                    .frame(width: 36, height: 3)
                    .padding(.top, 20)

                if let errorMessage {
                    Text(errorMessage)
                        .zappFont(.rowTitle, style: ZappColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)

                    if let errorDetail {
                        Text(errorDetail)
                            .zappFont(.mono, style: ZappColors.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.top, 10)
                    }

                    if let onRetry {
                        Button(action: onRetry) {
                            Text(localizable: .onboardingLoadingRetry)
                                .zappFont(.buttonSmall, style: ZappColors.text)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .overlay {
                                    Rectangle()
                                        .strokeBorder(ZappColors.text.color(colorScheme), lineWidth: 2)
                                }
                        }
                        .buttonStyle(.zappPress)
                        .padding(.top, 22)
                    }
                } else {
                    Text(message)
                        .zappFont(.rowTitle, color: .white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)

                    TimelineView(.periodic(from: .now, by: 0.4)) { context in
                        let active = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
                        HStack(spacing: 10) {
                            ForEach(0..<3, id: \.self) { index in
                                Rectangle()
                                    .fill(
                                        ZappColors.text.color(colorScheme)
                                            .opacity(index == active ? 1 : 0.28)
                                    )
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                    .frame(height: 10)
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ZappColors.accent.color(colorScheme))
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ZappLoadingWave: Shape {
    var heightFraction: CGFloat

    var animatableData: CGFloat {
        get { heightFraction }
        set { heightFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0.00, 0.18), (0.08, 0.56), (0.17, 0.32), (0.25, 0.78),
            (0.34, 0.45), (0.43, 0.88), (0.53, 0.38), (0.62, 0.68),
            (0.72, 0.30), (0.82, 0.82), (0.91, 0.48), (1.00, 0.66)
        ]
        let bandHeight = rect.height * heightFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for point in points {
            path.addLine(
                to: CGPoint(
                    x: rect.minX + rect.width * point.0,
                    y: rect.maxY - bandHeight * point.1
                )
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
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
                        Text(localizable: .onboardingSeedTitle)
                            .zappFont(.onboardingSeedTitle, style: ZappColors.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(localizable: .onboardingSeedSubtitle)
                            .zappFont(.onboardingSub, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)

                        seedGrid
                            .padding(.top, 20)

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

private struct ZappOnboardingPrimaryDock<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(ZappColors.surface.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.text.color(colorScheme), lineWidth: 1)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
    }
}

private struct ZappOnboardingProgress: View {
    @Environment(\.colorScheme) private var colorScheme

    let step: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { segment in
                Rectangle()
                    .fill(
                        (segment <= step ? ZappColors.accent : ZappColors.border)
                            .color(colorScheme)
                    )
                    .frame(height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .onboardingProgressAccessibility))
    }
}

private struct ZappOnboardingGhostNumber: View {
    let number: Int

    var body: some View {
        Text(String(format: "%02d", number))
            .zappFont(.onboardingGhost, style: ZappColors.surfaceAlt)
            .accessibilityHidden(true)
            .offset(x: 6, y: -22)
    }
}

private struct ZappOnboardingEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .zappFont(.eyebrow, style: ZappColors.accentText)
            .fixedSize(horizontal: false, vertical: true)
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

struct RecoverySeedPhraseEntryView: View {
    enum FocusTextField: Hashable {
        case field(Int)
    }

    @Environment(\.colorScheme) var colorScheme

    @Perception.Bindable var store: StoreOf<RestoreWalletCoordFlow>

    @FocusState private var focusedField: FocusTextField?
    @State private var keyboardVisible: Bool = false

    init(store: StoreOf<RestoreWalletCoordFlow>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(localizable: .restoreWalletTitle)
                            .zFont(.semiBold, size: 24, style: Design.Text.primary)
                            .padding(.top, 20)
                            .onLongPressGesture {
#if DEBUG
                                store.send(.debugPasteSeed)
#endif
                            }
                        
                        Text(localizable: .restoreWalletInfo)
                            .zFont(size: 14, style: Design.Text.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                        
                        ForEach(0..<8, id: \.self) { j in
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    WithPerceptionTracking {
                                        HStack(spacing: 0) {
                                            Text("\(j * 3 + i + 1)")
                                                .zFont(.medium, size: 14, style: Design.Tags.tcCountFg)
                                                .frame(minWidth: 12)
                                                .padding(.vertical, 2)
                                                .padding(.horizontal, 4)
                                                .background {
                                                    RoundedRectangle(cornerRadius: Design.Radius._lg)
                                                        .fill(Design.Tags.tcCountBg.color(colorScheme))
                                                }
                                                .padding(.trailing, 4)
                                            
                                            TextField("", text: $store.words[j * 3 + i])
                                                .zFont(size: 16, style: Design.Text.primary)
                                                .disableAutocorrection(true)
                                                .textInputAutocapitalization(.never)
                                                .focused($focusedField, equals: .field((j * 3 + i)))
                                                .keyboardType(.alphabet)
                                                .submitLabel(.next)
                                                .onSubmit {
                                                    focusedField = ((j * 3 + i) < 23)
                                                    ? .field((j * 3 + i) + 1)
                                                    : .field(0)
                                                }
                                        }
                                        .padding(6)
                                        .background {
                                            RoundedRectangle(cornerRadius: Design.Radius._xl)
                                                .fill(
                                                    focusedField == .field(j * 3 + i)
                                                    ? Design.Surfaces.bgPrimary.color(colorScheme)
                                                    : Design.Surfaces.bgSecondary.color(colorScheme)
                                                )
                                                .background {
                                                    RoundedRectangle(cornerRadius: Design.Radius._xl)
                                                        .stroke(strokeColor(index: j * 3 + i), lineWidth: 2)
                                                }
                                        }
                                        .padding(2)
                                        .padding(.bottom, 4)
                                    }
                                }
                            }
                        }
                        
                        if keyboardVisible {
                            Color.clear
                                .frame(height: 44)
                        }
                    }
                    .screenHorizontalPadding()
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: .infinity)
            .trackKeyboardVisibility($keyboardVisible)
            .onChange(of: keyboardVisible) { value in
                store.send(.updateKeyboardFlag(value))
            }
            .onChange(of: focusedField) { handle in
                if case .field(let index) = handle {
                    store.send(.selectedIndex(index))
                }
                
                if handle == nil {
                    store.send(.selectedIndex(nil))
                }
            }
            .onChange(of: store.nextIndex) { value in
                if let nextIndex = value {
                    focusedField = .field(nextIndex)
                }
            }
            .onChange(of: store.isKeyboardVisible) { value in
                if keyboardVisible && !value {
                    keyboardVisible = value
                    focusedField = nil
                }
            }
            .applyScreenBackground()
            .navigationBarItems(
                trailing:
                    Button {
                        store.send(.helpSheetRequested)
                    } label: {
                        Asset.Assets.Icons.help.image
                            .zImage(size: 24, style: Design.Text.primary)
                            .padding(Design.Spacing.navBarButtonPadding)
                    }
            )
            .zashiBack(
                primaryAction: {
                    ZashiButton(String(localizable: .generalNext)) {
                        store.send(.nextTapped)
                    }
                    .disabled(!store.isValidSeed)
                }
            )
            .screenTitle(String(localizable: .importWalletButtonRestoreWallet))
            .overlay(
                VStack(spacing: 0) {
                    Spacer()
                    
                    Asset.Colors.primary.color
                        .frame(height: 1)
                        .opacity(0.1)
                    
                    HStack(alignment: .center) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(store.suggestedWords, id: \.self) { suggestedWord in
                                    Button {
                                        store.send(.suggestedWordTapped(suggestedWord))
                                    } label: {
                                        Text(suggestedWord)
                                            .zFont(size: 16, style: Design.Text.primary)
                                            .fixedSize()
                                            .padding(8)
                                            .background {
                                                RoundedRectangle(cornerRadius: Design.Radius._xl)
                                                    .fill(Design.Surfaces.bgSecondary.color(colorScheme))
                                            }
                                    }
                                }
                            }
                            .padding(.leading, 4)
                        }
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Design.Surfaces.bgSecondary.color(colorScheme).opacity(0.7), location: 0.9),
                                    .init(color: Design.Surfaces.bgSecondary.color(colorScheme).opacity(0), location: 0.98)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 38)
                        
                        Spacer()
                        
                        Button {
                            focusedField = nil
                        } label: {
                            Text(String(localizable: .generalDone).uppercased())
                                .zFont(.regular, size: 14, style: Design.Text.primary)
                        }
                        .padding(.trailing, 24)
                        .padding(.leading, 4)
                    }
                    .applyScreenBackground()
                    .frame(height: keyboardVisible ? 44 : 0)
                    .frame(maxWidth: .infinity)
                    .opacity(keyboardVisible ? 1 : 0)
                }
            )
        }
    }
    
    private func strokeColor(index: Int) -> Color {
        !store.wordsValidity[index]
        ? Design.Inputs.ErrorFilled.stroke.color(colorScheme)
        : focusedField == .field(index)
        ? Design.Text.primary.color(colorScheme)
        : Design.Surfaces.bgSecondary.color(colorScheme)
    }
}
