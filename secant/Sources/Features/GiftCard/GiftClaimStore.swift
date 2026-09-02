// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// Turns a tapped gift link into money in this wallet, honestly: not-yet-confirmed is never
/// "empty", "empty" is never "collected", and a claim in flight is neither claimed nor unclaimed.
@Reducer
struct GiftClaim {
    enum Stage: Equatable {
        case loading
        case needsWallet
        case preview
        case consent(blocksToScan: Int64)
        case claiming
        case done
        /// Our broadcast, not yet final — the re-check is the only honest exit.
        case claimConfirming
        /// Funds present, under the confirmation threshold. Re-checks itself; no button.
        case pendingConfirmations
        case awaitingFunding
        case alreadyClaimed
    }

    /// Every error names what is true about the money.
    enum ClaimError: Equatable {
        case malformedLink
        case wrongNetwork
        case birthdayAboveTip
        case newerFormat
        case walletNotReady
        case linkUnavailable
        case notBroadcast
        case underfunded
        case unreachable
        case scanStalled
        case paramsUnavailable
        case failed
    }

    @ObservableState
    struct State: Equatable {
        /// The intake token this screen was opened with; spent on first load.
        var token: String?
        /// The held link. Retries re-use this, never the intake store — its token was spent on
        /// the way in. Never logged; the state's debug dump is redacted.
        var rawLink: String?
        var stage: Stage = .loading
        var payload: GiftLinkPayload?
        var cardAddress: String?
        var hasWallet = false
        var progress: GiftClaimProgress?
        var confirmations: Int?
        var requiredConfirmations = giftRequiredConfirmations
        var inFlightTxids: [String] = []
        var error: ClaimError?
        var isClaiming = false
        var canStopClaim = false
        var isForeground = true
        var isLocked = false
        @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil

        var amount: Zatoshi? {
            payload.flatMap { Int64($0.amountZatoshi) }.map(Zatoshi.init)
        }

        var fiatText: String? {
            guard let amount, let conversion = currencyConversion else { return nil }
            let text: String = conversion.convert(amount)
            return text
        }

        /// Past its advisory expiry — shown as a note, never enforced.
        var isPastExpiry: Bool {
            guard let expiresAt = payload?.expiresAt, let date = GiftLinkCodec.parseInstant(expiresAt) else {
                return false
            }
            return date < Date.now
        }
    }

    enum Action {
        case backgrounded
        case claimFinished(GiftClaimOutcome)
        case claimFailed(ClaimError)
        case claimTapped
        case confirmationsUpdated(Int?)
        case consentConfirmed
        case createWalletTapped
        case delegate(Delegate)
        case doneTapped
        case finalitySettled
        case onAppear
        case previewFailed(ClaimError)
        case previewLoaded(GiftClaimPreview)
        case progressUpdated(GiftClaimProgress)
        case recheckTicked
        case retryTapped
        case stopScanTapped
        case submitStarted
        case teardown
        case unlocked
        case verdictArrived(GiftBirthdayVerdict)
        case verdictFailed(ClaimError)
        case walletAppeared

        enum Delegate: Equatable {
            case dismiss
            case routeToOnboarding
        }
    }

    private enum CancelId {
        case claim
        case confirmWatch
        case counter
        case recheck
        case verdict
        case walletWait
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.pendingGiftLinks) var pendingGiftLinks
    @Dependency(\.walletStorage) var walletStorage

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // The token is spent exactly once; a screen recreated over a spent token shows
                // the link-unavailable copy ("tap the link again where you received it").
                if state.rawLink == nil {
                    guard let token = state.token, let raw = pendingGiftLinks.take(token) else {
                        state.stage = .preview
                        state.error = .linkUnavailable
                        return .none
                    }
                    state.rawLink = raw
                }
                return loadPreview(&state)

            case .previewLoaded(let preview):
                state.payload = preview.payload
                state.cardAddress = preview.cardAddress
                state.hasWallet = preview.hasWallet
                state.error = nil
                switch preview.collected {
                case .alreadyClaimed:
                    state.stage = .alreadyClaimed
                    return .none
                case .claimed:
                    state.stage = .done
                    return .none
                default:
                    break
                }
                if !preview.inFlightClaimTxids.isEmpty {
                    state.inFlightTxids = preview.inFlightClaimTxids
                    state.stage = .claimConfirming
                    return armConfirming(&state)
                }
                guard preview.hasWallet else {
                    state.stage = .needsWallet
                    return awaitWallet()
                }
                // The params download can start before the recipient has decided — the spend
                // needs them and the scan does not.
                return .merge(
                    .run { _ in
                        @Dependency(\.giftProvingParams) var giftProvingParams
                        await giftProvingParams.prefetch()
                    },
                    verdictEffect(payload: preview.payload)
                )

            case .previewFailed(let error):
                state.stage = .preview
                state.error = error
                return .none

            case .verdictArrived(let verdict):
                switch verdict {
                case .proceed:
                    state.stage = .preview
                case .needsConsent(let blocks):
                    state.stage = .consent(blocksToScan: blocks)
                }
                return .none

            case .verdictFailed(let error):
                guard error == .walletNotReady else {
                    state.stage = .preview
                    state.error = error
                    return .none
                }
                // A wait to retry, never a verdict on the card: loop while the tip is unknown.
                guard let payload = state.payload else { return .none }
                return verdictEffect(payload: payload, delaySeconds: 2)

            case .consentConfirmed:
                state.stage = .preview
                return .none

            case .claimTapped:
                // A bearer seed must not scan behind the lock screen. `isForeground` is what
                // enforces that today; nothing sets `isLocked`, so that conjunct is inert.
                guard !state.isClaiming, state.isForeground, !state.isLocked else { return .none }
                guard let payload = state.payload, let cardAddress = state.cardAddress else { return .none }
                state.stage = .claiming
                state.isClaiming = true
                state.canStopClaim = true
                state.error = nil
                state.progress = nil
                return .run { send in
                    do {
                        let outcome = try await ClaimGiftCard()(
                            payload: payload,
                            cardAddress: cardAddress,
                            onProgress: { progress in
                                Task { await send(.progressUpdated(progress)) }
                            },
                            // Fires past the receipt marker, where the tail is shielded and there
                            // is nothing left to stop.
                            onSubmitStarted: { await send(.submitStarted) }
                        )
                        // Unstructured: the shielded tail outlives a cancelled effect, which drops
                        // every `send` it makes.
                        await Task { await send(.claimFinished(outcome)) }.value
                    } catch is CancellationError {
                        // The recipient stopped the scan; the datasource discarded the unstarted
                        // receipt on its way out.
                    } catch {
                        await send(.claimFailed(ClaimError(claiming: error)))
                    }
                }
                .cancellable(id: CancelId.claim, cancelInFlight: true)

            case .progressUpdated(let progress):
                state.progress = progress
                return .none

            case .submitStarted:
                state.canStopClaim = false
                return .none

            case .claimFinished(let outcome):
                state.isClaiming = false
                state.canStopClaim = false
                switch outcome {
                case .claimed(_, let txIds):
                    state.inFlightTxids = txIds
                    state.stage = .done
                    return armConfirming(&state)
                case .notYetSpendable(_, _, let confirmations, let required):
                    state.confirmations = confirmations
                    state.requiredConfirmations = required
                    state.stage = .pendingConfirmations
                    return recheckTimer()
                case .awaitingFunding:
                    state.stage = .awaitingFunding
                    return .none
                case .alreadyClaimed:
                    state.stage = .alreadyClaimed
                    return .none
                case .underfunded:
                    state.stage = .preview
                    state.error = .underfunded
                    return .none
                case .notBroadcast(let result):
                    // Our txids may be in flight even on a failed fold; any fallback keeps the
                    // claim-confirming framing rather than putting a Claim button over money that
                    // may already be moving.
                    let txIds: [String]
                    switch result {
                    case .success(let ids), .failure(let ids, _, _), .grpcFailure(let ids, _), .partial(let ids, _):
                        txIds = ids
                    }
                    state.error = .notBroadcast
                    if !txIds.isEmpty {
                        state.inFlightTxids = txIds
                        state.stage = .claimConfirming
                        return armConfirming(&state)
                    }
                    state.stage = .preview
                    return .none
                }

            case .claimFailed(let error):
                state.isClaiming = false
                state.canStopClaim = false
                state.error = error
                state.stage = state.inFlightTxids.isEmpty ? .preview : .claimConfirming
                return .none

            case .stopScanTapped:
                guard state.isClaiming, state.canStopClaim else { return .none }
                state.isClaiming = false
                state.canStopClaim = false
                state.stage = state.inFlightTxids.isEmpty ? .preview : .claimConfirming
                return .cancel(id: CancelId.claim)

            case .recheckTicked:
                guard state.stage == .pendingConfirmations, state.isForeground, !state.isLocked else { return .none }
                return .send(.claimTapped)

            case .retryTapped:
                switch state.stage {
                case .awaitingFunding, .preview:
                    return .send(.claimTapped)
                case .claimConfirming:
                    // A claim that will never mine is indistinguishable from a slow one from
                    // here — the re-check is the only honest exit.
                    return .send(.claimTapped)
                default:
                    return .none
                }

            case .confirmationsUpdated(let confirmations):
                state.confirmations = confirmations
                return .none

            case .finalitySettled:
                return .none

            case .createWalletTapped:
                guard let raw = state.rawLink else { return .none }
                // The claim screen is about to be left behind and its token is already spent;
                // the deferred slot is the only thing standing between the recipient and
                // re-finding the message after onboarding.
                pendingGiftLinks.deferLink(raw)
                state.rawLink = nil
                return .send(.delegate(.routeToOnboarding))

            case .walletAppeared:
                state.hasWallet = true
                guard state.stage == .needsWallet else { return .none }
                return loadPreview(&state)

            case .doneTapped:
                return .send(.delegate(.dismiss))

            case .backgrounded:
                state.isForeground = false
                // The scan must not continue past the lock screen; the shielded submit tail
                // publishes its outcome regardless. Foreground re-arms off the retained stage.
                let effects: [Effect<Action>] = [
                    .cancel(id: CancelId.claim),
                    .cancel(id: CancelId.recheck),
                    .cancel(id: CancelId.confirmWatch),
                    .cancel(id: CancelId.counter)
                ]
                if state.isClaiming {
                    state.isClaiming = false
                    state.canStopClaim = false
                    if state.stage == .claiming {
                        state.stage = state.inFlightTxids.isEmpty ? .preview : .claimConfirming
                    }
                }
                return .merge(effects)

            case .unlocked:
                state.isForeground = true
                state.isLocked = false
                switch state.stage {
                case .pendingConfirmations:
                    return recheckTimer()
                case .claimConfirming, .done:
                    return armConfirming(&state)
                default:
                    return .none
                }

            case .teardown:
                if let raw = state.rawLink {
                    pendingGiftLinks.release(raw)
                }
                return .merge(
                    .cancel(id: CancelId.claim),
                    .cancel(id: CancelId.confirmWatch),
                    .cancel(id: CancelId.counter),
                    .cancel(id: CancelId.recheck),
                    .cancel(id: CancelId.verdict),
                    .cancel(id: CancelId.walletWait)
                )

            case .delegate:
                return .none
            }
        }
    }

}

extension GiftClaim {
    private func loadPreview(_ state: inout State) -> Effect<Action> {
        guard let raw = state.rawLink else { return .none }
        state.stage = .loading
        return .run { send in
            // Settle any receipt whose claim has since confirmed, so the preview lookup tells a
            // finished claim from one in flight.
            await ConfirmGiftClaim().reconcile()
            do {
                let preview = try await ClaimGiftCard().preview(raw)
                await send(.previewLoaded(preview))
            } catch {
                await send(.previewFailed(ClaimError(previewing: error)))
            }
        }
    }

    private func verdictEffect(payload: GiftLinkPayload, delaySeconds: Double? = nil) -> Effect<Action> {
        .run { send in
            if let delaySeconds {
                try await mainQueue.sleep(for: .seconds(delaySeconds))
            }
            do {
                let verdict = try await ClaimGiftCard().birthdayVerdict(payload)
                await send(.verdictArrived(verdict))
            } catch is GiftClaimNotReady {
                await send(.verdictFailed(.walletNotReady))
            } catch let error as GiftLinkError where error == .birthdayAboveTip {
                await send(.verdictFailed(.birthdayAboveTip))
            } catch {
                await send(.verdictFailed(.failed))
            }
        }
        .cancellable(id: CancelId.verdict, cancelInFlight: true)
    }

    /// Foreground-only. Two effects: one completes as the finality signal, one streams the
    /// confirmation count. Arming compares awaited txids by cancel-in-flight, so a replacement
    /// claim displaces a dead watch.
    private func armConfirming(_ state: inout State) -> Effect<Action> {
        guard state.isForeground, let address = state.cardAddress, !state.inFlightTxids.isEmpty else { return .none }
        let txids = state.inFlightTxids
        return .merge(
            .run { send in
                await ConfirmGiftClaim()(address: address, claimTxids: txids)
                await send(.finalitySettled)
            }
            .cancellable(id: CancelId.confirmWatch, cancelInFlight: true),
            .run { send in
                for await confirmations in ConfirmGiftClaim().observeClaimConfirmations(address: address) {
                    await send(.confirmationsUpdated(confirmations))
                }
            }
            .cancellable(id: CancelId.counter, cancelInFlight: true)
        )
    }

    /// Foreground-only, 45 seconds.
    private func recheckTimer() -> Effect<Action> {
        .run { send in
            try await mainQueue.sleep(for: .seconds(45))
            await send(.recheckTicked)
        }
        .cancellable(id: CancelId.recheck, cancelInFlight: true)
    }

    /// The claim screen survives in place while the recipient onboards: it reloads when a wallet
    /// appears.
    private func awaitWallet() -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                if (try? walletStorage.areKeysPresent()) == true {
                    await send(.walletAppeared)
                    return
                }
                try await mainQueue.sleep(for: .seconds(1))
            }
        }
        .cancellable(id: CancelId.walletWait, cancelInFlight: true)
    }
}

private extension GiftClaim.ClaimError {
    init(previewing error: Error) {
        if let link = error as? GiftLinkError {
            switch link {
            case .networkMismatch:
                self = .wrongNetwork
            case .newerFormat, .unsupportedVersion:
                self = .newerFormat
            default:
                self = .malformedLink
            }
            return
        }
        if error is GiftReceiptStoreUnreadable {
            self = .failed
            return
        }
        self = .malformedLink
    }

    init(claiming error: Error) {
        if let engine = error as? GiftClaimEngineError {
            switch engine {
            case .unreachable: self = .unreachable
            case .scanStalled: self = .scanStalled
            case .paramsUnavailable: self = .paramsUnavailable
            case .stopped: self = .failed
            }
            return
        }
        if error is GiftClaimNotReady {
            self = .walletNotReady
            return
        }
        self = .failed
    }
}

// The raw link and payload hold the bearer mnemonic; debug dumps of the state must never carry
// them.
extension GiftClaim.State: CustomDumpStringConvertible {
    var customDumpDescription: String {
        "GiftClaim.State(stage: \(stage), error: \(String(describing: error)), redacted)"
    }
}
