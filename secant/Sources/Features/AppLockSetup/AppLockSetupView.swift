//
//  AppLockSetupView.swift
//  Zashi
//

import ComposableArchitecture
import SwiftUI

struct AppLockSetupView: View {
    @Environment(\.colorScheme)
    private var colorScheme
    @Perception.Bindable var store: StoreOf<AppLockSetup>

    var body: some View {
        WithPerceptionTracking {
            Group {
                switch store.step {
                case .choice:
                    choice
                case .createPIN, .confirmPIN:
                    AppPINEntryView(
                        title: store.step == .createPIN
                            ? String(localizable: .onboardingPINCreateTitle)
                            : String(localizable: .onboardingPINConfirmTitle),
                        subtitle: store.step == .createPIN
                            ? String(localizable: .onboardingPINCreateSubtitle)
                            : String(localizable: .onboardingPINConfirmSubtitle),
                        errorMessage: store.errorMessage,
                        digitCount: store.pin.count,
                        isInputEnabled: !store.isProcessing,
                        showsOnboardingProgress: true,
                        onBack: { store.send(.backTapped) },
                        onKey: { store.send(.pinKeyTapped($0)) }
                    )
                case .biometric:
                    biometric
                }
            }
            .onAppear { store.send(.onAppear) }
        }
    }

    private var choice: some View {
        VStack(spacing: 0) {
            onboardingProgress
                .padding(.horizontal, 28)
                .padding(.top, 20)

            ZStack(alignment: .topTrailing) {
                Text("03")
                    .zappFont(.display, style: ZappColors.surfaceAlt)
                    .font(.system(size: 104, weight: .black))
                    .accessibilityHidden(true)
                    .offset(x: 6, y: -22)

                VStack(alignment: .leading, spacing: 0) {
                    Text(localizable: .onboardingSecurityBadge)
                        .zappFont(.eyebrow, style: ZappColors.accentText)

                    Text(localizable: .onboardingSecurityTitle)
                        .zappFont(.displaySecondary, style: ZappColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    Text(localizable: .onboardingSecuritySubtitle)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    Spacer(minLength: 24)

                    VStack(spacing: 0) {
                        choiceRow(
                            glyph: "◎",
                            title: String(localizable: .onboardingSecurityBiometric),
                            subtitle: store.isBiometricAvailable
                                ? String(localizable: .onboardingSecurityBiometricSubtitle)
                                : String(localizable: .onboardingBiometricUnavailable),
                            isHighlighted: store.isBiometricAvailable
                        ) {
                            store.send(.biometricTapped)
                        }

                        choiceRow(
                            glyph: "✱",
                            title: String(localizable: .onboardingSecurityPIN),
                            subtitle: String(localizable: .onboardingSecurityPINSubtitle),
                            isHighlighted: !store.isBiometricAvailable
                        ) {
                            store.send(.pinTapped)
                        }
                    }
                    .overlay {
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    }
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .navigationBarBackButtonHidden(true)
    }

    private var biometric: some View {
        VStack(spacing: 0) {
            onboardingProgress
                .padding(.horizontal, 28)
                .padding(.top, 20)

            VStack(spacing: 0) {
                Spacer()

                Text("◎")
                    .zappFont(
                        .display,
                        style: store.errorMessage == nil ? ZappColors.accentText : ZappColors.danger
                    )

                Text(localizable: .onboardingBiometricTitle)
                    .zappFont(.displaySecondary, style: ZappColors.text)
                    .padding(.top, 20)

                Text(store.errorMessage ?? String(localizable: .onboardingBiometricSubtitle))
                    .zappFont(
                        .body,
                        style: store.errorMessage == nil ? ZappColors.textMuted : ZappColors.danger
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 28)

            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(
                    title: store.isProcessing
                        ? String(localizable: .onboardingBiometricVerifying)
                        : String(localizable: .onboardingBiometricEnable),
                    isEnabled: store.isBiometricAvailable && !store.isProcessing
                ) {
                    store.send(.enableBiometricTapped)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .navigationBarBackButtonHidden(true)
    }

    private var onboardingProgress: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { _ in
                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .onboardingProgressAccessibility))
    }

    private func choiceRow(
        glyph: String,
        title: String,
        subtitle: String,
        isHighlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
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
    }
}
