//
//  SecretAuthGateView.swift
//  Zapp
//
//  The two view halves every secret screen needs: the PIN pad the gate shows while it waits, and
//  the hide triggers. The triggers are the same four `ChatProfileSecretOverlays` and
//  `OnboardingSeedBackup` use — resign-active (which is what the app switcher snapshot fires
//  first), background, a screen recording starting, and the screen going away — so a revealed key
//  leaves memory the moment the app stops being frontmost.
//

import ComposableArchitecture
import SwiftUI
import UIKit

extension View {
    /// Android's `PinVerifyOverlay`, composed into the screen itself rather than presented: a modal
    /// presentation can take the presenting view's `onDisappear` with it, which on a secret screen
    /// is the hide trigger, tearing the PIN pad down the moment it appears.
    func secretAuthGateOverlay(store: StoreOf<SecretAuthGate>) -> some View {
        modifier(SecretAuthGateOverlay(store: store))
    }

    /// Hides the screen's secrets whenever it could be photographed, recorded, or left in the app
    /// switcher, and marks it privacy-sensitive while one is up.
    func secretScreenGuards(isShowingSecret: Bool, onHide: @escaping () -> Void) -> some View {
        privacySensitive(isShowingSecret)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                onHide()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                onHide()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                if UIScreen.main.isCaptured {
                    onHide()
                }
            }
    }
}

private struct SecretAuthGateOverlay: ViewModifier {
    @Perception.Bindable var store: StoreOf<SecretAuthGate>

    func body(content: Content) -> some View {
        WithPerceptionTracking {
            content
                .overlay {
                    if let entry = store.pinEntry {
                        AppPINEntryView(
                            title: String(localizable: .appLockPINVerifyTitle),
                            subtitle: String(localizable: .appLockPINVerifySubtitle),
                            errorMessage: entry.errorMessage,
                            digitCount: entry.pin.count,
                            isInputEnabled: !entry.isVerifying && entry.lockoutSeconds == 0,
                            onBack: { store.send(.pinCancelled) },
                            onKey: { store.send(.pinKeyTapped($0)) }
                        )
                    }
                }
        }
    }
}
