// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// The amount screen for a Peer cash-out: how much USDC to offer, who pays you, and in which
/// currencies.
///
/// It never starts a ZEC bridge. A cash-out spends Base USDC the user already has, so being short
/// is an inline stop with an explicit "Top up from ZEC" beside it — moving their ZEC without asking
/// is not something an amount field should do.
@Reducer
struct PeerCashOutForm {
    @ObservableState
    struct State: Equatable {
        let destinationCode: String

        var destination: PeerDestination?
        var amountInput = ""
        var handleInput = ""
        /// Ordered. The first is the primary: the currency the rate and the market note are quoted
        /// in. A `Set` has no ordering contract, and `first` on one that has been added to and
        /// removed from is how a GBP rate ends up labelled EUR.
        var selectedCurrencyCodes: [String] = []
        var spendable: PeerSpendableBalance = .loading
        var rate: PeerRate?
        var market: PeerMarketReading?
        var handleCheck: PeerHandleCheck?
        /// The rail's own rules decide who gets paid, so an unanswered check is not a pass. It is
        /// carried separately from `handleCheck` because "we could not ask" and "the rail said no"
        /// need different words.
        var isHandleCheckUnanswered = false
        var recommendedMinimum: UsdcAmount = .zero
        /// Orders already on chain, plus the attempts too young for the indexer to know about.
        var activeOrders: [PeerOrder] = []
        var runs: [PeerRun] = []
        /// Claimed on the tap. The reservation a start records is only observable a frame later, so
        /// two taps would both pass the same rendered balance check and open two cash-outs.
        var isSubmitting = false
        var errorMessage: String?

        var primaryCurrencyCode: String? { selectedCurrencyCodes.first }

        var amount: UsdcAmount? {
            guard !amountInput.isEmpty, let amount = UsdcAmount(whole: amountInput), amount.isPositive else {
                return nil
            }
            return amount
        }

        var normalizedHandle: String? { handleCheck?.normalized }

        /// Over the spendable balance is a stop, not a silent bridge. Anything already promised to
        /// an unfinished attempt is subtracted first, so three orders cannot share one balance, and
        /// a balance we could not read blocks rather than waves through.
        var amountError: String? {
            guard let amount else { return nil }
            if amount < recommendedMinimum {
                return String(localizable: .peerFormErrorBelowMinimum(recommendedMinimum.display))
            }
            if case .unavailable = spendable { return String(localizable: .peerFormErrorBalanceUnavailable) }
            guard let available = spendable.available else { return nil }
            if !spendable.covers(amount) {
                return String(localizable: .peerFormErrorAboveAvailable(available.display))
            }
            return nil
        }

        /// A warning, never a block: a large order is many fills over hours, not one, and it is
        /// still a valid order.
        var sizingWarning: String? {
            guard amountError == nil, market?.isOversized == true, let average = market?.averageFill else {
                return nil
            }
            return String(localizable: .peerFormSizingWarning(average.display))
        }

        var handleError: String? {
            guard !handleInput.isEmpty else { return nil }
            if isHandleCheckUnanswered { return String(localizable: .peerFormErrorHandleUnchecked) }
            guard let check = handleCheck, !check.isAcceptable else { return nil }
            return String(localizable: .peerFormErrorHandleFormat)
        }

        /// The attempts the order list cannot answer for yet, so the amount already promised to one
        /// is visible beside the orders rather than only missing from the balance.
        var unindexedRuns: [PeerRun] {
            let indexed = Set(activeOrders.map(\.depositID))
            return runs.filter { $0.isAwaitingIndex(in: indexed) }
        }

        /// Set only where normalizing changed what was typed — Chime's leading `$`, a stripped `@`,
        /// a lowercased revtag. A buyer pays what was registered, so the user sees it first.
        var normalizedEcho: String? {
            guard let check = handleCheck, check.changedWhatWasTyped, let normalized = check.normalized else {
                return nil
            }
            return String(localizable: .peerFormHandleRegistersAs(normalized))
        }

        /// Zelle and Chime cannot be checked with the platform, so the user is told rather than
        /// reassured by a validation that never ran.
        var showsUnverifiedHandleWarning: Bool {
            handleCheck.map { $0.isAcceptable && !$0.validatesLive } ?? false
        }

        var canSubmit: Bool {
            amount != nil
                && amountError == nil
                && handleError == nil
                && normalizedHandle != nil
                && !selectedCurrencyCodes.isEmpty
                && spendable.available != nil
                && !isSubmitting
        }

        /// Adds, or removes and promotes. Removing the last one is refused: a deposit with no
        /// currency cannot be filled by anyone.
        mutating func toggleCurrency(_ code: String) {
            guard destination?.offersCurrencyChoice == true else { return }
            if let index = selectedCurrencyCodes.firstIndex(of: code) {
                guard selectedCurrencyCodes.count > 1 else { return }
                selectedCurrencyCodes.remove(at: index)
            } else {
                selectedCurrencyCodes.append(code)
            }
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case capabilitiesLoaded(PeerCapabilities, storedHandle: String?)
        case balanceLoaded(PeerSpendableBalance)
        case ordersLoaded([PeerOrder])
        case marketLoaded(rate: PeerRate?, market: PeerMarketReading?)
        case handleChecked(destinationCode: String, rawInput: String, check: PeerHandleCheck)
        case handleCheckFailed(destinationCode: String, rawInput: String)
        case runnerStateChanged(PeerRunnerState)
        case amountChanged(String)
        case handleChanged(String)
        case currencyTapped(String)
        case topUpTapped
        case continueTapped
        case started(attemptID: String)
        case failed(String)
        case orderTapped(depositID: String)
        case attemptTapped(attemptID: String)
        case backTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case close
            case topUp
            case openAttempt(attemptID: String)
            case openOrder(depositID: String)
        }
    }

    @Dependency(\.peerCashOut) var peerCashOut
    @Dependency(\.continuousClock) var continuousClock

    private enum CancelID {
        case runner
        case handle
        case market
        case balance
        case orders
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.errorMessage = nil
                return .merge(
                    loadCapabilities(destinationCode: state.destinationCode),
                    refreshBalance(),
                    refreshOrders(),
                    .run { send in
                        for await runnerState in try await peerCashOut.runnerState() {
                            await send(.runnerStateChanged(runnerState))
                        }
                    }
                    .cancellable(id: CancelID.runner, cancelInFlight: true)
                )

            case .onDisappear:
                // The wallet-lifetime runner keeps driving attempts. This screen owns only these
                // observations and debounced reads, so dismissal must not let `.empty` from a later
                // wallet reset trigger fresh session-backed requests through an invisible form.
                return .merge(
                    .cancel(id: CancelID.runner),
                    .cancel(id: CancelID.handle),
                    .cancel(id: CancelID.market),
                    .cancel(id: CancelID.balance),
                    .cancel(id: CancelID.orders)
                )

            case let .capabilitiesLoaded(capabilities, storedHandle):
                state.recommendedMinimum = capabilities.recommendedMinimum
                state.destination = capabilities.destination(code: state.destinationCode)
                if state.selectedCurrencyCodes.isEmpty {
                    state.selectedCurrencyCodes = state.destination?.defaultCurrencyCodes ?? []
                }
                if state.handleInput.isEmpty, let storedHandle {
                    state.handleInput = storedHandle
                }
                return .merge(checkHandle(state.destinationCode, state.handleInput), refreshMarket(state))

            case let .balanceLoaded(spendable):
                state.spendable = spendable
                return .none

            case let .ordersLoaded(orders):
                state.activeOrders = orders
                return .none

            case let .marketLoaded(rate, market):
                state.rate = rate
                state.market = market
                return .none

            case let .handleChecked(destinationCode, rawInput, check):
                guard destinationCode == state.destinationCode, rawInput == state.handleInput else {
                    return .none
                }
                state.handleCheck = check
                state.isHandleCheckUnanswered = false
                return .none

            // Silence here is what leaves a filled-in form permanently un-submittable with nothing
            // on screen saying why — including the stored handle the screen pre-fills on first open.
            case let .handleCheckFailed(destinationCode, rawInput):
                guard destinationCode == state.destinationCode, rawInput == state.handleInput else {
                    return .none
                }
                state.isHandleCheckUnanswered = true
                return .none

            case let .runnerStateChanged(runnerState):
                state.runs = runnerState.runs
                // An attempt settling frees the amount it reserved and turns into an order the
                // indexer can answer for, so both readings are stale the moment one does.
                return .merge(refreshBalance(), refreshOrders())

            case let .amountChanged(value):
                state.amountInput = DecimalAmountInput.sanitized(value)
                state.errorMessage = nil
                return refreshMarket(state)

            case let .handleChanged(value):
                state.handleInput = value
                // A normalized handle authorizes the irreversible escrow recipient. Invalidate it
                // in the same reducer turn as the edit so the debounce cannot leave the previous
                // recipient submit-ready, and accept only the response keyed to this exact input.
                state.handleCheck = nil
                state.isHandleCheckUnanswered = false
                state.errorMessage = nil
                return checkHandle(state.destinationCode, value)

            case let .currencyTapped(code):
                state.toggleCurrency(code)
                // The rate is quoted in the primary, so a change of primary invalidates it. Cleared
                // rather than kept: a stale number under a new label is worse than no number.
                state.rate = nil
                state.market = nil
                return refreshMarket(state)

            case .topUpTapped:
                return .send(.delegate(.topUp))

            case .continueTapped:
                guard state.canSubmit, let amount = state.amount, let handle = state.normalizedHandle else {
                    return .none
                }
                state.isSubmitting = true
                state.errorMessage = nil
                let draft = PeerCashOutDraft(
                    destinationCode: state.destinationCode,
                    handle: handle,
                    currencyCodes: state.selectedCurrencyCodes,
                    amount: amount
                )
                return .run { send in
                    await send(.started(attemptID: try await peerCashOut.startCashOut(draft)))
                } catch: { error, send in
                    await send(.failed(error.localizedDescription))
                }

            case let .started(attemptID):
                state.isSubmitting = false
                state.amountInput = ""
                return .send(.delegate(.openAttempt(attemptID: attemptID)))

            case let .failed(message):
                state.isSubmitting = false
                state.errorMessage = message
                return .none

            case let .orderTapped(depositID):
                return .send(.delegate(.openOrder(depositID: depositID)))

            case let .attemptTapped(attemptID):
                return .send(.delegate(.openAttempt(attemptID: attemptID)))

            case .backTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }

    private func loadCapabilities(destinationCode: String) -> Effect<Action> {
        .run { send in
            let capabilities = try await peerCashOut.capabilities()
            let handle = try? await peerCashOut.storedHandle(destinationCode)
            await send(.capabilitiesLoaded(capabilities, storedHandle: handle))
        } catch: { error, send in
            await send(.failed(error.localizedDescription))
        }
    }

    private func refreshBalance() -> Effect<Action> {
        .run { send in
            await send(.balanceLoaded(try await peerCashOut.spendableBalance()))
        } catch: { _, send in
            await send(.balanceLoaded(.unavailable))
        }
        .cancellable(id: CancelID.balance, cancelInFlight: true)
    }

    private func refreshOrders() -> Effect<Action> {
        .run { send in
            await send(.ordersLoaded(try await peerCashOut.activeOrders()))
        } catch: { _, _ in
            // A failed order read leaves the last known list on screen; it is not a form error.
        }
        .cancellable(id: CancelID.orders, cancelInFlight: true)
    }

    /// Debounced because normalizing crosses into Kotlin, where the rail's rules live. Repeating
    /// them in Swift would be a second copy of the one thing that decides who gets paid.
    private func checkHandle(_ destinationCode: String, _ raw: String) -> Effect<Action> {
        .run { send in
            try await continuousClock.sleep(for: .milliseconds(200))
            let check = try await peerCashOut.normalizeHandle(destinationCode, raw)
            await send(.handleChecked(destinationCode: destinationCode, rawInput: raw, check: check))
        } catch: { _, send in
            await send(.handleCheckFailed(destinationCode: destinationCode, rawInput: raw))
        }
        .cancellable(id: CancelID.handle, cancelInFlight: true)
    }

    /// The rate is re-read rather than cached: it is indicative, and one shown as live has to be.
    /// The market reading behind it is cached in Kotlin, so this is one round trip, not two.
    private func refreshMarket(_ state: State) -> Effect<Action> {
        guard let currency = state.primaryCurrencyCode else { return .none }
        let destinationCode = state.destinationCode
        let amount = state.amount
        return .run { send in
            try await continuousClock.sleep(for: .milliseconds(300))
            async let rate = peerCashOut.rate(currency)
            async let market = peerCashOut.market(destinationCode, currency, amount)
            await send(.marketLoaded(rate: try await rate, market: try await market))
        } catch: { _, _ in
            // Fails open: generic copy, never an invented estimate.
        }
        .cancellable(id: CancelID.market, cancelInFlight: true)
    }
}
