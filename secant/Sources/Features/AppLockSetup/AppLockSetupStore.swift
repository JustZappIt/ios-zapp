//
//  AppLockSetupStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation

@Reducer
struct AppLockSetup {
    enum Step: Equatable {
        case biometric
        case choice
        case confirmPIN
        case createPIN
    }

    @ObservableState
    struct State: Equatable {
        var errorMessage: String?
        var firstPIN = ""
        var isBiometricAvailable = false
        var isProcessing = false
        var pin = ""
        var step = Step.choice

        static let initial = State()
    }

    enum Action: Equatable {
        case backTapped
        case biometricAuthenticationFinished(Bool)
        case biometricTapped
        case enableBiometricTapped
        case onAppear
        case pinConfigurationFinished(Bool)
        case pinKeyTapped(Character)
        case pinTapped
        case setupFinished
    }

    @Dependency(\.appSecurity)
    var appSecurity
    @Dependency(\.localAuthentication)
    var localAuthentication

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isBiometricAvailable = localAuthentication.method() != .none
                return .none

            case .pinTapped:
                state.errorMessage = nil
                state.firstPIN = ""
                state.pin = ""
                state.step = .createPIN
                return .none

            case .biometricTapped:
                state.errorMessage = state.isBiometricAvailable
                    ? nil
                    : String(localizable: .onboardingBiometricUnavailable)
                state.step = .biometric
                return .none

            case .backTapped:
                state.errorMessage = nil
                state.firstPIN = ""
                state.pin = ""
                state.isProcessing = false
                state.step = .choice
                return .none

            case let .pinKeyTapped(key):
                guard !state.isProcessing else {
                    return .none
                }
                state.errorMessage = nil
                if key == "⌫" {
                    if !state.pin.isEmpty {
                        state.pin.removeLast()
                    }
                    return .none
                }
                guard key.isNumber, state.pin.count < 6 else {
                    return .none
                }
                state.pin.append(key)
                guard state.pin.count == 6 else {
                    return .none
                }

                if state.step == .createPIN {
                    state.firstPIN = state.pin
                    state.pin = ""
                    state.step = .confirmPIN
                    return .none
                }

                guard state.pin == state.firstPIN else {
                    state.errorMessage = String(localizable: .onboardingPINMismatch)
                    state.firstPIN = ""
                    state.pin = ""
                    state.step = .createPIN
                    return .none
                }

                state.isProcessing = true
                let pin = state.pin
                return .run { send in
                    let succeeded: Bool
                    do {
                        try await appSecurity.configurePIN(pin)
                        succeeded = true
                    } catch {
                        succeeded = false
                    }
                    await send(.pinConfigurationFinished(succeeded))
                }

            case .enableBiometricTapped:
                guard state.isBiometricAvailable, !state.isProcessing else {
                    state.errorMessage = String(localizable: .onboardingBiometricUnavailable)
                    return .none
                }
                state.isProcessing = true
                state.errorMessage = nil
                return .run { send in
                    await send(.biometricAuthenticationFinished(await localAuthentication.authenticate()))
                }

            case let .biometricAuthenticationFinished(succeeded):
                guard succeeded else {
                    state.isProcessing = false
                    state.errorMessage = String(localizable: .onboardingBiometricFailed)
                    return .none
                }
                do {
                    try appSecurity.configureBiometric()
                    return .send(.setupFinished)
                } catch {
                    state.isProcessing = false
                    state.errorMessage = String(localizable: .appLockStorageError)
                    return .none
                }

            case let .pinConfigurationFinished(succeeded):
                state.isProcessing = false
                if succeeded {
                    return .send(.setupFinished)
                }
                state.errorMessage = String(localizable: .appLockStorageError)
                state.firstPIN = ""
                state.pin = ""
                state.step = .createPIN
                return .none

            case .setupFinished:
                return .none
            }
        }
    }
}
