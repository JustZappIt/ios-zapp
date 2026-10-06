//
//  SecretAuthGateStore.swift
//  Zapp
//
//  Android's `SecretAuthGate`: a secret reveal is gated on whichever app lock the user configured
//  — the system biometric prompt, the app PIN pad (with the same lockout the app-lock screen
//  enforces, via `appSecurity`), or nothing at all when the policy allows it.
//
//  The gate only answers "may this be revealed?". It never reads a secret itself: the parent does
//  that on `.delegate(.authenticated)`, so a cancelled prompt can never touch the keychain or the
//  SDK. `ChatProfileSecrets.swift` predates this and carries its own copy of the same logic.
//

import ComposableArchitecture
import Foundation

@Reducer
struct SecretAuthGate {
    /// Android's `SecretAuthPolicy`.
    enum Policy: Equatable {
        /// No app lock configured lets the reveal straight through, as Android's `AuthMethod.NONE`
        /// does for the seed phrase and the P2P key.
        case allowUnconfigured
        /// The reveal always authenticates. Android refuses outright when no app lock is
        /// configured, which leaves a user without one no way to export at all; iOS asks for the
        /// device owner (biometrics or passcode) instead, so the reveal is still never unauthenticated.
        case requireAuthentication
    }

    @ObservableState
    struct State: Equatable {
        /// True only between the system biometric sheet going up and its result coming back. That
        /// sheet makes the app resign active, which is one of the hide triggers — without this flag
        /// the screen would cancel the very authentication it is waiting on.
        var isAwaitingBiometric = false

        /// Non-nil while the PIN pad is on screen.
        var pinEntry: PINEntry?

        struct PINEntry: Equatable {
            var pin = ""
            var errorMessage: String?
            var lockoutSeconds = 0
            var isVerifying = false
        }

        var isAuthenticating: Bool { isAwaitingBiometric || pinEntry != nil }

        init() { }
    }

    enum Action: Equatable {
        case start(Policy)
        case biometricFinished(Bool)
        case pinKeyTapped(PINKey)
        case pinVerificationFinished(PINVerificationResult)
        case pinLockoutTick
        case pinCancelled
        /// The screen is hiding its secrets (backgrounding, a recording starting, leaving). Drops
        /// the PIN pad silently; an in-flight biometric prompt is left to resolve on its own.
        case hide
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case authenticated
            /// A cancelled or failed prompt. The parent decides whether that is worth a message.
            case failed
        }
    }

    @Dependency(\.appSecurity) var appSecurity
    @Dependency(\.continuousClock) var continuousClock
    @Dependency(\.date) var date
    @Dependency(\.localAuthentication) var localAuthentication

    init() { }

    enum CancelID {
        case pinLockout
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .start(let policy):
                guard !state.isAuthenticating else { return .none }

                switch appSecurity.authenticationMethod() {
                case .biometric:
                    return biometricPrompt(&state)

                case .pin:
                    state.pinEntry = State.PINEntry(lockoutSeconds: appSecurity.lockoutRemaining(date.now()))
                    return (state.pinEntry?.lockoutSeconds ?? 0) > 0 ? lockoutTimer() : .none

                case .none:
                    switch policy {
                    case .allowUnconfigured:
                        return .send(.delegate(.authenticated))
                    case .requireAuthentication:
                        return biometricPrompt(&state)
                    }
                }

            case .biometricFinished(let succeeded):
                guard state.isAwaitingBiometric else { return .none }

                state.isAwaitingBiometric = false
                return .send(.delegate(succeeded ? .authenticated : .failed))

            case .pinKeyTapped(let key):
                guard var entry = state.pinEntry, !entry.isVerifying, entry.lockoutSeconds == 0 else {
                    return .none
                }

                entry.errorMessage = nil
                PINInput.apply(key, to: &entry.pin)

                guard PINInput.isComplete(entry.pin) else {
                    state.pinEntry = entry
                    return .none
                }

                let pin = entry.pin
                let now = date.now()
                entry.pin = ""
                entry.isVerifying = true
                state.pinEntry = entry

                return .run { send in
                    await send(.pinVerificationFinished(await appSecurity.verifyPIN(pin, now)))
                }

            case .pinVerificationFinished(let result):
                return handlePINVerification(result, state: &state)

            case .pinLockoutTick:
                guard var entry = state.pinEntry else { return .none }

                entry.lockoutSeconds = appSecurity.lockoutRemaining(date.now())
                entry.errorMessage = entry.lockoutSeconds > 0
                    ? String(localizable: .appLockPINLocked(String(entry.lockoutSeconds)))
                    : nil
                state.pinEntry = entry
                return entry.lockoutSeconds > 0 ? .none : .cancel(id: CancelID.pinLockout)

            case .pinCancelled:
                guard state.pinEntry != nil else { return .none }

                state.pinEntry = nil
                return .merge(
                    .cancel(id: CancelID.pinLockout),
                    .send(.delegate(.failed))
                )

            case .hide:
                state.pinEntry = nil
                return .cancel(id: CancelID.pinLockout)

            case .delegate:
                return .none
            }
        }
    }

    private func biometricPrompt(_ state: inout State) -> Effect<Action> {
        state.isAwaitingBiometric = true
        return .run { send in
            await send(.biometricFinished(await localAuthentication.authenticateAppLock()))
        }
    }

    /// Same three outcomes the app-lock screen handles, including the shared lockout window.
    private func handlePINVerification(_ result: PINVerificationResult, state: inout State) -> Effect<Action> {
        guard var entry = state.pinEntry else { return .none }
        entry.isVerifying = false

        switch result {
        case .success:
            state.pinEntry = nil
            return .merge(
                .cancel(id: CancelID.pinLockout),
                .send(.delegate(.authenticated))
            )

        case .incorrect:
            entry.errorMessage = String(localizable: .appLockPINIncorrect)
            state.pinEntry = entry
            return .none

        case .locked(let secondsRemaining):
            entry.lockoutSeconds = secondsRemaining
            entry.errorMessage = String(localizable: .appLockPINLocked(String(secondsRemaining)))
            state.pinEntry = entry
            return lockoutTimer()
        }
    }

    private func lockoutTimer() -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                try await continuousClock.sleep(for: .seconds(1))
                await send(.pinLockoutTick)
            }
        }
        .cancellable(id: CancelID.pinLockout, cancelInFlight: true)
    }
}
