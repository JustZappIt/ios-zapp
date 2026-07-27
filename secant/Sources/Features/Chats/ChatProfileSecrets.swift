//
//  ChatProfileSecrets.swift
//  Zapp
//
//  The two reveal surfaces from Android's ChatProfileVM: the recovery seed phrase and the
//  P2P wallet key.
//
//  Rules this file exists to enforce:
//
//  1. Nothing is read until the app lock says so. `initiateReveal` reproduces Android's
//     `initiateReveal()`: biometric prompt, PIN gate (with the same lockout the app-lock
//     screen enforces, via `appSecurity`), or straight through when no lock is configured.
//     The secret is fetched only after the gate passes — a cancelled prompt never touches
//     the keychain.
//  2. Neither secret is ever logged. Failures log a fixed string, never the value, and both
//     live in `RedactableString`, which is `Undescribable` outside DEBUG — so a `dump`, a
//     synthesized `description`, or a crash reporter walking state cannot serialise them.
//  3. They leave memory the instant the app stops being frontmost. `hideSensitiveContent`
//     clears both and is sent from `willResignActive`, `didEnterBackground`, a screen
//     recording starting, and `onDisappear` — the same four triggers `OnboardingSeedBackup`
//     uses in `RestoreWalletCoordFlowView`.
//

import ComposableArchitecture
import Foundation

extension ChatProfile {
    func secretsReduce() -> some Reducer<State, Action> {
        CombineReducers {
            authGateReduce()
            pinGateReduce()
            revealReduce()
            secretCopyReduce()
        }
    }

    /// Everything between "the user asked" and "the app lock said yes".
    private func authGateReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .seedPhraseTapped:
                return beginReveal(.seedPhrase, state: &state)

            case .p2pKeyTapped:
                return beginReveal(.p2pKey, state: &state)

                // A dismissed or failed prompt is silent, exactly like Android's empty catch
                // blocks for BiometricsCancelledException / BiometricsFailureException.
            case let .biometricFinished(target, succeeded):
                state.isAwaitingBiometric = false

                guard state.pendingSecret == target else { return .none }
                guard succeeded else {
                    state.pendingSecret = nil
                    return .none
                }
                return .send(.secretUnlocked(target))

            default:
                return .none
            }
        }
    }

    /// The PIN pad shown when the app lock is a PIN, including its lockout ticker.
    private func pinGateReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
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
                state.pinEntry = nil
                state.pendingSecret = nil
                return .cancel(id: CancelID.pinLockout)

            default:
                return .none
            }
        }
    }

    /// Same three outcomes the app-lock screen handles, including the shared lockout window.
    private func handlePINVerification(_ result: PINVerificationResult, state: inout State) -> Effect<Action> {
        guard var entry = state.pinEntry else { return .none }
        entry.isVerifying = false

        switch result {
        case .success:
            let target = state.pendingSecret
            state.pinEntry = nil
            return target.map { .send(.secretUnlocked($0)) } ?? .none

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

    /// Everything after the gate: reading, showing, copying, and destroying the secret.
    private func revealReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
                // The gate has passed: now, and only now, read the secret.
            case .secretUnlocked(let target):
                state.pendingSecret = nil
                state.secretFailed = false
                state.secretBlockedByCapture = false

                switch target {
                case .seedPhrase:
                    return .run { send in
                        do {
                            let words = try walletStorage.exportWallet()
                                .seedPhrase
                                .value()
                                .split(separator: " ")
                                .map { RedactableString(String($0)) }
                            await send(.seedLoaded(words))
                        } catch {
                            // Deliberately not interpolating `error`: a keychain error can echo
                            // back the item it was reading.
                            LoggerProxy.error("ChatProfile: seed phrase export failed")
                            await send(.secretLoadFailed)
                        }
                    }

                case .p2pKey:
                    return .run { [offramp] send in
                        do {
                            await send(.p2pKeyLoaded(try await offramp.exportWalletKey()))
                        } catch {
                            LoggerProxy.error("ChatProfile: P2P wallet key export failed")
                            await send(.secretLoadFailed)
                        }
                    }
                }

            case .seedLoaded(let words):
                state.seedWords = words
                return .none

            case .p2pKeyLoaded(let key):
                state.p2pKey = key
                return .none

            case .secretLoadFailed:
                state.secretFailed = true
                return .none

            case .secretDismissed, .hideSensitiveContent:
                return clearSecrets(&state)

            default:
                return .none
            }
        }
    }

    /// Copy-to-pasteboard, offered on the P2P dialog only.
    private func secretCopyReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .copyP2PAddressTapped:
                guard let key = state.p2pKey else { return .none }

                pasteboard.setString(RedactableString(key.address))
                state.didCopyP2PAddress = true
                state.didCopyP2PKey = false
                return copyIndicatorTimer()

                // Android's P2P dialog is the only one of the two that offers copy, and it offers
                // it for both fields. Its seed dialog has no copy button, so neither does ours —
                // a 24-word phrase on the system pasteboard is readable by every other app.
            case .copyP2PKeyTapped:
                guard let key = state.p2pKey else { return .none }

                pasteboard.setString(key.privateKeyHex)
                state.didCopyP2PKey = true
                state.didCopyP2PAddress = false
                return copyIndicatorTimer()

            case .p2pCopyIndicatorExpired:
                state.didCopyP2PAddress = false
                state.didCopyP2PKey = false
                return .none

            default:
                return .none
            }
        }
    }

    /// Android's `initiateReveal()`: the method the user already chose for the app lock is the
    /// method that guards the secret. No lock configured means no gate — the same fall-through
    /// Android's `AuthMethod.NONE` takes.
    private func beginReveal(_ target: SecretTarget, state: inout State) -> Effect<Action> {
        guard state.pendingSecret == nil, !state.isShowingSecret else { return .none }

        state.secretFailed = false
        state.secretBlockedByCapture = false

        // `capturedDidChange` only fires on a TRANSITION, so a recording that was already
        // running when the profile opened never produced one. Ask outright before the gate:
        // there is no point authenticating into a secret that is being filmed.
        guard !screenCapture.isCaptured() else {
            state.secretBlockedByCapture = true
            return .none
        }

        switch appSecurity.authenticationMethod() {
        case .biometric:
            state.pendingSecret = target
            state.isAwaitingBiometric = true
            return .run { send in
                await send(.biometricFinished(target, await localAuthentication.authenticateAppLock()))
            }

        case .pin:
            state.pendingSecret = target
            state.pinEntry = State.PINEntry(lockoutSeconds: appSecurity.lockoutRemaining(date.now()))
            return (state.pinEntry?.lockoutSeconds ?? 0) > 0 ? lockoutTimer() : .none

        case .none:
            return .send(.secretUnlocked(target))
        }
    }

    /// Drops every byte of both secrets and everything that could hint at them.
    private func clearSecrets(_ state: inout State) -> Effect<Action> {
        state.seedWords.removeAll(keepingCapacity: false)
        state.p2pKey = nil
        state.didCopyP2PAddress = false
        state.didCopyP2PKey = false
        state.secretFailed = false
        state.secretBlockedByCapture = false

        // The gate itself survives its own biometric sheet — that sheet resigns the app active,
        // and cancelling here would strand a successful Face ID with nothing left to unlock.
        // Nothing sensitive is held: no secret has been read yet, the prompt always resolves
        // (a real backgrounding makes the system cancel it, which fails the gate), and
        // `biometricFinished` clears the flag either way.
        if !state.isAwaitingBiometric {
            state.pendingSecret = nil
            state.pinEntry = nil
        }

        return .merge(
            .cancel(id: CancelID.pinLockout),
            .cancel(id: CancelID.p2pCopyIndicator)
        )
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

    private func copyIndicatorTimer() -> Effect<Action> {
        .run { send in
            try await mainQueue.sleep(for: .seconds(2))
            await send(.p2pCopyIndicatorExpired)
        }
        .cancellable(id: CancelID.p2pCopyIndicator, cancelInFlight: true)
    }
}
