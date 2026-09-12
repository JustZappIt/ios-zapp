//
//  SecuritySettingsView.swift
//  Zashi
//

import ComposableArchitecture
import SwiftUI

struct SecuritySettingsView: View {
    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Perception.Bindable var store: StoreOf<SecuritySettings>

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                // Keep the menu underneath PIN/biometric steps so a partial back swipe reveals
                // the actual destination. Only the visible layer may handle a back gesture.
                menu
                    .zappSwipeBack(isEnabled: store.screen == .menu && !store.isProcessing) {
                        store.send(.backTapped)
                    }
                    .allowsHitTesting(store.screen == .menu)
                    .accessibilityHidden(store.screen != .menu)

                Group {
                    switch store.screen {
                    case .menu:
                        EmptyView()
                    case .verifyPIN:
                        AppPINEntryView(
                            title: String(localizable: .appLockPINVerifyTitle),
                            subtitle: String(localizable: .appLockPINVerifySubtitle),
                            errorMessage: store.errorMessage,
                            digitCount: store.pin.count,
                            isInputEnabled: !store.isProcessing && store.lockoutSeconds == 0,
                            onBack: { store.send(.backTapped) },
                            onKey: { store.send(.pinKeyTapped($0)) }
                        )
                    case .createPIN:
                        AppPINEntryView(
                            title: store.firstPIN.isEmpty
                                ? String(localizable: .appLockPINNewTitle)
                                : String(localizable: .onboardingPINConfirmTitle),
                            subtitle: store.firstPIN.isEmpty
                                ? String(localizable: .appLockPINNewSubtitle)
                                : String(localizable: .appLockPINNewConfirmSubtitle),
                            errorMessage: store.errorMessage,
                            digitCount: store.pin.count,
                            isInputEnabled: !store.isProcessing,
                            onBack: { store.send(.backTapped) },
                            onKey: { store.send(.pinKeyTapped($0)) }
                        )
                    case .enrollBiometric:
                        biometricEnrollment
                    }
                }
                .zappSwipeBack(isEnabled: store.screen != .menu && !store.isProcessing) { store.send(.backTapped) }
                // A completed swipe leaves its layer off-screen; the next step needs fresh drag state.
                .id(store.screen)
            }
            .onAppear { store.send(.onAppear) }
        }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: String(localizable: .appLockTitle))

            ScrollView {
                VStack(spacing: 0) {
                    methodContent { method in
                        VStack(spacing: 16) {
                            Text(method == .pin ? "✱" : "◎")
                                .zappFont(.display, style: ZappColors.accentText)
                                .frame(width: 84, height: 84)
                                .background(ZappColors.accentSoft.color(colorScheme))

                            Text(localizable: method == .pin ? .appLockPINDescription : .appLockBiometricDescription)
                                .zappFont(.body, style: ZappColors.textMuted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 32)

                    ZappSegmentedSelector(
                        options: [
                            String(localizable: .appLockPINOption),
                            String(localizable: .appLockBiometricOption)
                        ],
                        cellMinHeight: 48,
                        usesAccentSelection: true,
                        selectedIndex: store.selectedMethod == .pin ? 0 : 1
                    ) { index in
                        store.send(.selectedMethodChanged(index == 0 ? .pin : .biometric))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 28)

                    Text(localizable: .appLockActions)
                        .zappFont(.groupLabel, style: ZappColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 28)
                        .padding(.bottom, 8)

                    methodContent { method in
                        ZappRow(
                            title: method == .pin
                                ? String(localizable: .appLockChangePIN)
                                : String(localizable: .appLockReenrollBiometric),
                            subtitle: method == .pin
                                ? String(localizable: .appLockChangePINSubtitle)
                                : String(localizable: .appLockReenrollBiometricSubtitle),
                            icon: Asset.Assets.Icons.authKey.image,
                            iconTint: .accentText,
                            iconBackground: .accentSoft
                        ) {
                            store.send(.saveTapped)
                        }
                    }
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay {
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    }
                    .padding(.horizontal, 18)

                    if let message = store.successMessage {
                        Text(message)
                            .zappFont(.caption, style: ZappColors.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .zappFont(.caption, style: ZappColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                    }
                }
            }

            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(
                    title: String(localizable: .appLockSaveChanges),
                    isEnabled: store.selectedMethod != store.currentMethod
                        && !store.isProcessing
                        && (store.selectedMethod != .biometric || store.isBiometricAvailable)
                ) {
                    store.send(.saveTapped)
                }
            }
        }
        .background(ZappColors.bg.color(colorScheme))
        .navigationBarBackButtonHidden(true)
    }

    /// Both variants participate in layout so changing methods cannot move the selector or rows.
    /// Only the selected variant is interactive or announced by VoiceOver.
    private func methodContent<Content: View>(
        @ViewBuilder content: (AppAuthenticationMethod) -> Content
    ) -> some View {
        ZStack(alignment: .top) {
            content(.pin)
                .opacity(store.selectedMethod == .pin ? 1 : 0)
                .allowsHitTesting(store.selectedMethod == .pin)
                .accessibilityHidden(store.selectedMethod != .pin)
            content(.biometric)
                .opacity(store.selectedMethod == .biometric ? 1 : 0)
                .allowsHitTesting(store.selectedMethod == .biometric)
                .accessibilityHidden(store.selectedMethod != .biometric)
        }
        .animation(reduceMotion ? nil : ZappMotion.content, value: store.selectedMethod)
    }

    private var biometricEnrollment: some View {
        VStack(spacing: 0) {
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
                    isEnabled: !store.isProcessing
                ) {
                    store.send(.enrollBiometricTapped)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .navigationBarBackButtonHidden(true)
    }
}
