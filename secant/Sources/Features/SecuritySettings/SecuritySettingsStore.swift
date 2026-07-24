//
//  SecuritySettingsStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation

@Reducer
struct SecuritySettings {
    enum PINIntent: Equatable {
        case change
        case switchFromBiometric
        case switchToBiometric
    }

    enum Screen: Equatable {
        case createPIN(PINIntent)
        case enrollBiometric
        case menu
        case verifyPIN(PINIntent)
    }

    private enum CancelID {
        case lockoutTimer
    }

    @ObservableState
    struct State: Equatable {
        var currentMethod = AppAuthenticationMethod.none
        var errorMessage: String?
        var firstPIN = ""
        var isBiometricAvailable = false
        var isProcessing = false
        var lockoutSeconds = 0
        var pin = ""
        var screen = Screen.menu
        var selectedMethod = AppAuthenticationMethod.pin
        var successMessage: String?

        static let initial = State()
    }

    enum Action: Equatable {
        case backTapped
        case biometricAuthenticationFinished(PINIntent, Bool)
        case closeRequested
        case enrollBiometricTapped
        case lockoutTick
        case onAppear
        case pinConfigurationFinished(PINIntent, Bool)
        case pinKeyTapped(PINKey)
        case pinVerificationFinished(PINIntent, PINVerificationResult)
        case saveTapped
        case selectedMethodChanged(AppAuthenticationMethod)
    }

    @Dependency(\.appSecurity)
    var appSecurity
    @Dependency(\.continuousClock)
    var continuousClock
    @Dependency(\.date)
    var date
    @Dependency(\.localAuthentication)
    var localAuthentication

    var body: some Reducer<State, Action> {
        menuReducer()
        pinReducer()
        biometricReducer()
    }
}

private extension SecuritySettings {
    func menuReducer() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let method = appSecurity.authenticationMethod()
                state.currentMethod = method
                state.selectedMethod = method == .none ? .pin : method
                state.isBiometricAvailable = localAuthentication.method() != .none
                state.lockoutSeconds = appSecurity.lockoutRemaining(date.now())
                return state.lockoutSeconds > 0 ? lockoutTimer() : .none

            case let .selectedMethodChanged(method):
                guard method != .none else {
                    return .none
                }
                state.selectedMethod = method
                state.successMessage = nil
                return .none

            case .saveTapped:
                return saveChanges(state: &state)

            case .backTapped:
                if state.screen == .menu {
                    return .send(.closeRequested)
                }
                state.errorMessage = nil
                state.firstPIN = ""
                state.isProcessing = false
                state.pin = ""
                state.screen = .menu
                return .cancel(id: CancelID.lockoutTimer)

            case .closeRequested:
                return .none

            default:
                return .none
            }
        }
    }

    func saveChanges(state: inout State) -> Effect<Action> {
        state.errorMessage = nil
        state.successMessage = nil
        state.firstPIN = ""
        state.pin = ""

        switch (state.currentMethod, state.selectedMethod) {
        case (.pin, .pin):
            state.screen = .verifyPIN(.change)
        case (.pin, .biometric):
            guard state.isBiometricAvailable else {
                state.errorMessage = String(localizable: .onboardingBiometricUnavailable)
                return .none
            }
            state.screen = .verifyPIN(.switchToBiometric)
        case (.biometric, .pin):
            return authenticateBiometric(intent: .switchFromBiometric, state: &state)
        case (.biometric, .biometric):
            return authenticateBiometric(intent: .switchToBiometric, state: &state)
        case (.none, .pin):
            state.screen = .createPIN(.switchFromBiometric)
        case (.none, .biometric):
            return authenticateBiometric(intent: .switchToBiometric, state: &state)
        default:
            break
        }
        return .none
    }
}

private extension SecuritySettings {
    func pinReducer() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case let .pinKeyTapped(key):
                return handlePINKey(key, state: &state)

            case let .pinVerificationFinished(intent, result):
                return handlePINVerification(intent: intent, result: result, state: &state)

            case .lockoutTick:
                state.lockoutSeconds = appSecurity.lockoutRemaining(date.now())
                state.errorMessage = state.lockoutSeconds > 0
                    ? lockoutMessage(state.lockoutSeconds)
                    : nil
                return .none

            case let .pinConfigurationFinished(intent, succeeded):
                handlePINConfiguration(intent: intent, succeeded: succeeded, state: &state)
                return .none

            default:
                return .none
            }
        }
    }

    func handlePINKey(_ key: PINKey, state: inout State) -> Effect<Action> {
        guard !state.isProcessing, state.lockoutSeconds == 0 else {
            return .none
        }
        state.errorMessage = nil
        PINInput.apply(key, to: &state.pin)

        switch state.screen {
        case let .verifyPIN(intent):
            guard PINInput.isComplete(state.pin) else {
                return .none
            }
            return verifyPIN(intent: intent, state: &state)
        case let .createPIN(intent):
            return createPIN(intent: intent, state: &state)
        default:
            return .none
        }
    }

    func verifyPIN(intent: PINIntent, state: inout State) -> Effect<Action> {
        state.isProcessing = true
        let pin = state.pin
        let now = date.now()
        state.pin = ""
        return .run { send in
            let result = await appSecurity.verifyPIN(pin, now)
            await send(.pinVerificationFinished(intent, result))
        }
    }

    func createPIN(intent: PINIntent, state: inout State) -> Effect<Action> {
        let submission = PINInput.submit(pin: state.pin, firstPIN: state.firstPIN)
        state.pin = submission.pin
        state.firstPIN = submission.firstPIN
        switch submission.result {
        case .incomplete:
            return .none
        case .confirmationRequired:
            return .none
        case .mismatch:
            state.errorMessage = String(localizable: .onboardingPINMismatch)
            return .none
        case let .confirmed(pin):
            state.isProcessing = true
            return .run { send in
                let succeeded: Bool
                do {
                    try await appSecurity.configurePIN(pin)
                    succeeded = true
                } catch {
                    succeeded = false
                }
                await send(.pinConfigurationFinished(intent, succeeded))
            }
        }
    }

    func handlePINVerification(
        intent: PINIntent,
        result: PINVerificationResult,
        state: inout State
    ) -> Effect<Action> {
        state.isProcessing = false
        switch result {
        case .success:
            state.errorMessage = nil
            state.firstPIN = ""
            state.pin = ""
            state.screen = intent == .switchToBiometric
                ? .enrollBiometric
                : .createPIN(.change)
            return .none

        case .incorrect:
            state.errorMessage = String(localizable: .appLockPINIncorrect)
            return .none

        case let .locked(secondsRemaining):
            state.lockoutSeconds = secondsRemaining
            state.errorMessage = lockoutMessage(secondsRemaining)
            return lockoutTimer()
        }
    }

    func handlePINConfiguration(
        intent: PINIntent,
        succeeded: Bool,
        state: inout State
    ) {
        state.isProcessing = false
        guard succeeded else {
            state.errorMessage = String(localizable: .appLockStorageError)
            state.firstPIN = ""
            state.pin = ""
            return
        }

        state.currentMethod = .pin
        state.selectedMethod = .pin
        state.errorMessage = nil
        state.firstPIN = ""
        state.pin = ""
        state.screen = .menu
        state.successMessage = intent == .change
            ? String(localizable: .appLockPINChanged)
            : String(localizable: .appLockPINSwitched)
    }

    func lockoutTimer() -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                try await continuousClock.sleep(for: .seconds(1))
                await send(.lockoutTick)
            }
        }
        .cancellable(id: CancelID.lockoutTimer, cancelInFlight: true)
    }

    func lockoutMessage(_ seconds: Int) -> String {
        String(localizable: .appLockPINLocked(String(seconds)))
    }
}

private extension SecuritySettings {
    func biometricReducer() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .enrollBiometricTapped:
                return authenticateBiometric(intent: .switchToBiometric, state: &state)

            case let .biometricAuthenticationFinished(intent, succeeded):
                return handleBiometricAuthentication(intent: intent, succeeded: succeeded, state: &state)

            default:
                return .none
            }
        }
    }

    func authenticateBiometric(
        intent: PINIntent,
        state: inout State
    ) -> Effect<Action> {
        guard state.isBiometricAvailable, !state.isProcessing else {
            state.errorMessage = String(localizable: .onboardingBiometricUnavailable)
            return .none
        }
        state.isProcessing = true
        state.errorMessage = nil
        return .run { send in
            await send(.biometricAuthenticationFinished(intent, await localAuthentication.authenticateAppLock()))
        }
    }

    func handleBiometricAuthentication(
        intent: PINIntent,
        succeeded: Bool,
        state: inout State
    ) -> Effect<Action> {
        state.isProcessing = false
        guard succeeded else {
            state.errorMessage = String(localizable: .onboardingBiometricFailed)
            return .none
        }

        if intent == .switchFromBiometric {
            state.firstPIN = ""
            state.pin = ""
            state.screen = .createPIN(intent)
            return .none
        }

        do {
            try appSecurity.configureBiometric()
            state.currentMethod = .biometric
            state.selectedMethod = .biometric
            state.errorMessage = nil
            state.screen = .menu
            state.successMessage = String(localizable: .appLockBiometricUpdated)
        } catch {
            state.errorMessage = String(localizable: .appLockStorageError)
        }
        return .none
    }
}
