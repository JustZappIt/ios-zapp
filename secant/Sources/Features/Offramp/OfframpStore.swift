// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

@Reducer
struct Offramp {
    enum CorridorContext: Equatable {
        case settings
        case payment
    }

    enum Page: Equatable {
        case corridors
        case scanner
        case amount
        case topUp
        case progress
        case history
    }

    @ObservableState
    struct State: Equatable {
        var page: Page
        var corridorContext: CorridorContext
        var corridors: [OfframpCorridor] = []
        var selectedCurrencyCode: String
        var draftCurrencyCode: String
        var scan: OfframpScanResult?
        var fiatAmount = ""
        var quote: OfframpQuoteModel?
        var progress: [OfframpProgressModel] = []
        var history: [OfframpHistoryModel] = []
        var isLoading = false
        var errorMessage: String?
        var hasCheckpoint = false
        var isCheckpointDiscardConfirmationPresented = false
        var checkpointCurrencyCode: String?
        var hasTopUpCheckpoint = false
        var topUpCheckpointMicros: String?
        var isResumingCheckpoint = false
        var account: OfframpAccountModel?
        var topUpAmount = ""
        var topUpFiatAmount = ""
        var isAddressCopied = false
        var isRefundConfirmationPresented = false
        var isPayConfirmationPresented = false
        var isTopUpConfirmationPresented = false
        var isTopUpDiscardConfirmationPresented = false
        var bridgePreview: OfframpBridgePreview?
        var historyReturnPage: Page?
        var isTopUpAmountInsufficient = false
        var isTopUpValidationLoading = false
        var topUpValidatedMicros: String?

        var selectedCorridor: OfframpCorridor? {
            corridors.first { $0.currencyCode == selectedCurrencyCode }
        }

        var draftCorridor: OfframpCorridor? {
            corridors.first { $0.currencyCode == draftCurrencyCode }
        }

        var latestProgress: OfframpProgressModel? { progress.last }

        var canSaveCorridor: Bool {
            !isLoading && draftCurrencyCode != selectedCurrencyCode
        }

        init(page: Page = .amount, corridorContext: CorridorContext = .settings) {
            let saved = UserDefaults.standard.string(forKey: Offramp.currencyPreferenceKey) ?? "INR"
            self.page = page
            self.corridorContext = corridorContext
            self.selectedCurrencyCode = saved
            self.draftCurrencyCode = saved
        }

        static func initial(
            page: Page = .amount,
            corridorContext: CorridorContext = .settings
        ) -> Self {
            Self(page: page, corridorContext: corridorContext)
        }
    }

    enum Action: Equatable {
        case onAppear
        case loadedCorridors([OfframpCorridor], String?, String?)
        case loadFailed(String)
        case accountLoaded(OfframpAccountModel)
        case draftCorridorTapped(String)
        case chooseCorridorTapped
        case saveCorridorTapped
        case resumeCheckpointTapped
        case scanPayload(String)
        case scanParsed(OfframpScanResult)
        case scanFailed(String)
        case fiatAmountChanged(String)
        case quoteTapped
        case quoteLoaded(OfframpQuoteModel)
        case payTapped
        case payQuoteRefreshed(OfframpQuoteModel)
        case payConfirmed
        case payDismissed
        case addFundsTapped
        case topUpAmountChanged(String)
        case topUpFiatAmountChanged(String)
        case topUpValidationRequested
        case topUpValidationLoaded(String)
        case topUpValidationFailed(String, String, Bool)
        case startTopUpTapped
        case topUpPreviewLoaded(OfframpBridgePreview)
        case topUpConfirmed
        case topUpDismissed
        case progressReceived(OfframpProgressModel)
        case progressFinished
        case historyTapped
        case historyLoaded([OfframpHistoryModel])
        case recoverTapped(String?)
        case refundTapped
        case refundPreviewLoaded(OfframpBridgePreview)
        case refundConfirmed
        case refundDismissed
        case copyAccountAddressTapped
        case discardCheckpointTapped
        case discardCheckpointConfirmed
        case discardCheckpointDismissed
        case checkpointDiscarded
        case discardTopUpCheckpointTapped
        case discardTopUpCheckpointConfirmed
        case discardTopUpCheckpointDismissed
        case topUpCheckpointDiscarded
        case checkpointsLoaded(String?, String?)
        case operationCancelled(Page)
        case cancelAll
        case backTapped
        case retryTapped
        case delegate(Delegate)

        enum Delegate: Equatable { case close }
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var continuousClock

    private enum CancelID {
        case operation
        case request
        case topUpValidation
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.errorMessage = nil
                let page = state.page
                return .run { send in
                    do {
                        async let corridors = offramp.corridors()
                        async let checkpointCurrency = offramp.checkpointCurrencyCode()
                        async let topUpCheckpoint = offramp.topUpCheckpointMicros()
                        await send(.loadedCorridors(
                            try await corridors,
                            try await checkpointCurrency,
                            try await topUpCheckpoint
                        ))
                        if page == .history {
                            async let history = offramp.history()
                            async let account = offramp.accountSummary()
                            await send(.historyLoaded(try await history))
                            await send(.accountLoaded(try await account))
                        } else if page == .corridors || page == .amount || page == .topUp {
                            await send(.accountLoaded(try await offramp.accountSummary()))
                        }
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case let .loadedCorridors(corridors, checkpointCurrency, topUpCheckpoint):
                state.corridors = corridors
                state.checkpointCurrencyCode = checkpointCurrency
                state.hasCheckpoint = checkpointCurrency != nil
                state.topUpCheckpointMicros = topUpCheckpoint
                state.hasTopUpCheckpoint = topUpCheckpoint != nil
                if !corridors.contains(where: { $0.currencyCode == state.selectedCurrencyCode }) {
                    state.selectedCurrencyCode = corridors.first?.currencyCode ?? "INR"
                    state.draftCurrencyCode = state.selectedCurrencyCode
                }
                state.isLoading = false
                return .none

            case .loadFailed(let message), .scanFailed(let message):
                state.isLoading = false
                state.errorMessage = message
                return .none

            case .accountLoaded(let account):
                state.account = account
                state.isLoading = false
                if state.page == .topUp, Self.validTopUpMicros(state.topUpAmount) != nil {
                    return .send(.topUpValidationRequested)
                }
                return .none

            case .draftCorridorTapped(let code):
                state.draftCurrencyCode = code
                return .none

            case .chooseCorridorTapped:
                state.draftCurrencyCode = state.selectedCurrencyCode
                state.corridorContext = .payment
                state.page = .corridors
                return .none

            case .saveCorridorTapped:
                guard state.canSaveCorridor else { return .none }
                state.selectedCurrencyCode = state.draftCurrencyCode
                UserDefaults.standard.set(state.selectedCurrencyCode, forKey: Self.currencyPreferenceKey)
                state.quote = nil
                state.errorMessage = nil
                if state.corridorContext == .payment {
                    state.page = .amount
                    return .none
                }
                return .send(.delegate(.close))

            case .resumeCheckpointTapped:
                guard let currency = state.checkpointCurrencyCode else { return .none }
                state.selectedCurrencyCode = currency
                state.draftCurrencyCode = currency
                state.isResumingCheckpoint = true
                state.page = .progress
                state.progress = []
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        let stream = try await offramp.resumePayment()
                        for await status in stream { await send(.progressReceived(status)) }
                        await send(.progressFinished)
                    } catch OfframpClientError.authenticationCancelled {
                        await send(.operationCancelled(.amount))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.operation, cancelInFlight: true)

            case .scanPayload(let payload):
                guard !state.isLoading else { return .none }
                guard !state.hasCheckpoint || state.isResumingCheckpoint else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                let currency = state.selectedCurrencyCode
                return .run { send in
                    do { await send(.scanParsed(try await offramp.parseQR(currency, payload))) }
                    catch { await send(.scanFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .scanParsed(let scan):
                state.scan = scan
                state.page = .progress
                state.isLoading = true
                return .run { send in
                    do { try await offramp.submitPaymentDetails(scan) }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .fiatAmountChanged(let value):
                state.fiatAmount = Self.sanitizedAmount(value)
                state.quote = nil
                state.errorMessage = nil
                return .none

            case .quoteTapped:
                guard Self.hasPositiveAmount(state.fiatAmount), !state.isLoading else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                let currency = state.selectedCurrencyCode
                let amount = state.fiatAmount
                return .run { send in
                    do { await send(.quoteLoaded(try await offramp.quote(currency, amount))) }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .quoteLoaded(let quote):
                guard Self.isAllowedOfframpQuote(quote) else {
                    state.quote = nil
                    state.isLoading = false
                    state.errorMessage = "Maximum 100 USDC per offramp."
                    return .none
                }
                state.quote = quote
                state.isLoading = false
                return .none

            case .payTapped:
                guard let quote = state.quote, quote.canPayFromBase, !state.isLoading else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        await send(.payQuoteRefreshed(try await offramp.quote(quote.currencyCode, quote.fiatAmount)))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .payQuoteRefreshed(let refreshed):
                let changed = state.quote != refreshed
                state.quote = refreshed
                state.isLoading = false
                if changed {
                    state.isPayConfirmationPresented = true
                    return .none
                }
                return .send(.payConfirmed)

            case .payConfirmed:
                guard let quote = state.quote, quote.canPayFromBase, !state.isLoading else { return .none }
                state.isPayConfirmationPresented = false
                state.page = .progress
                state.progress = []
                state.isLoading = true
                return .run { send in
                    do {
                        let stream = try await offramp.pay(quote, nil)
                        for await status in stream { await send(.progressReceived(status)) }
                        await send(.progressFinished)
                    } catch OfframpClientError.authenticationCancelled {
                        await send(.operationCancelled(.amount))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.operation, cancelInFlight: true)

            case .payDismissed:
                state.isPayConfirmationPresented = false
                return .none

            case .addFundsTapped:
                state.topUpAmount = state.quote?.shortfallDisplay == "0" ? "" : state.quote?.shortfallDisplay ?? ""
                state.topUpFiatAmount = Self.fiatTopUpDisplay(
                    usdcAmount: state.topUpAmount,
                    sellRate: state.quote?.sellRate
                )
                if let micros = state.topUpCheckpointMicros {
                    state.topUpAmount = Self.usdcDisplay(micros)
                    state.topUpFiatAmount = Self.fiatTopUpDisplay(
                        usdcAmount: state.topUpAmount,
                        sellRate: state.quote?.sellRate
                    )
                }
                state.page = .topUp
                state.isLoading = true
                return .run { send in
                    do { await send(.accountLoaded(try await offramp.accountSummary())) }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .topUpAmountChanged(let value):
                state.topUpAmount = Self.sanitizedAmount(value)
                state.errorMessage = nil
                return .send(.topUpValidationRequested)

            case .topUpFiatAmountChanged(let value):
                state.topUpFiatAmount = Self.sanitizedAmount(value)
                state.errorMessage = nil
                guard
                    let fiat = Decimal(string: state.topUpFiatAmount),
                    let rateText = state.quote?.sellRate,
                    let rate = Decimal(string: rateText),
                    rate > 0
                else {
                    state.topUpAmount = ""
                    return .send(.topUpValidationRequested)
                }
                var usdc = fiat / rate
                var rounded = Decimal()
                NSDecimalRound(&rounded, &usdc, 6, .down)
                state.topUpAmount = NSDecimalNumber(decimal: rounded).stringValue
                return .send(.topUpValidationRequested)

            case .topUpValidationRequested:
                state.topUpValidatedMicros = nil
                state.isTopUpAmountInsufficient = false
                state.isTopUpValidationLoading = false
                guard
                    let micros = Self.validTopUpMicros(state.topUpAmount),
                    state.account?.canBridgeToBase == true
                else { return .cancel(id: CancelID.topUpValidation) }
                state.isTopUpValidationLoading = true
                return .run { send in
                    try await continuousClock.sleep(for: .milliseconds(450))
                    do {
                        _ = try await offramp.previewTopUp(micros)
                        await send(.topUpValidationLoaded(micros))
                    } catch {
                        await send(.topUpValidationFailed(
                            micros,
                            Self.topUpErrorMessage(error),
                            Self.isInsufficientBalanceError(error)
                        ))
                    }
                }
                .cancellable(id: CancelID.topUpValidation, cancelInFlight: true)

            case .topUpValidationLoaded(let micros):
                guard Self.validTopUpMicros(state.topUpAmount) == micros else { return .none }
                state.topUpValidatedMicros = micros
                state.isTopUpValidationLoading = false
                state.isTopUpAmountInsufficient = false
                state.errorMessage = nil
                return .none

            case let .topUpValidationFailed(micros, message, isInsufficient):
                guard Self.validTopUpMicros(state.topUpAmount) == micros else { return .none }
                state.topUpValidatedMicros = nil
                state.isTopUpValidationLoading = false
                state.isTopUpAmountInsufficient = isInsufficient
                state.errorMessage = message
                return .none

            case .startTopUpTapped:
                guard
                    let micros = Self.validTopUpMicros(state.topUpAmount),
                    state.topUpValidatedMicros == micros,
                    !state.isTopUpAmountInsufficient,
                    !state.isTopUpValidationLoading,
                    !state.isLoading
                else { return .none }
                if let stored = state.topUpCheckpointMicros, stored != micros {
                    state.errorMessage = "A different Base top-up is already in progress. Resume or discard it first."
                    return .none
                }
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        await send(.topUpPreviewLoaded(try await offramp.previewTopUp(micros)))
                    } catch { await send(.loadFailed(Self.topUpErrorMessage(error))) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .topUpPreviewLoaded(let preview):
                state.bridgePreview = preview
                state.isLoading = false
                state.isTopUpConfirmationPresented = true
                return .none

            case .topUpConfirmed:
                guard
                    let micros = Self.validTopUpMicros(state.topUpAmount),
                    state.bridgePreview != nil,
                    !state.isLoading
                else { return .none }
                state.isTopUpConfirmationPresented = false
                state.page = .progress
                state.progress = []
                state.isLoading = true
                return .run { send in
                    do {
                        let stream = try await offramp.bridgeToBase(micros, nil)
                        for await status in stream { await send(.progressReceived(status)) }
                        await send(.progressFinished)
                    } catch OfframpClientError.authenticationCancelled {
                        await send(.operationCancelled(.topUp))
                    } catch { await send(.loadFailed(Self.topUpErrorMessage(error))) }
                }
                .cancellable(id: CancelID.operation, cancelInFlight: true)

            case .topUpDismissed:
                state.isTopUpConfirmationPresented = false
                state.bridgePreview = nil
                return .none

            case .progressReceived(let status):
                if state.progress.last?.kind == status.kind {
                    state.progress[state.progress.count - 1] = status
                } else {
                    state.progress.append(status)
                }
                state.isLoading = !status.isTerminal
                if status.kind == "waiting_for_payment_details" {
                    state.page = .scanner
                    state.isLoading = false
                }
                if status.isTerminal {
                    state.hasCheckpoint = false
                    state.checkpointCurrencyCode = nil
                    state.isResumingCheckpoint = false
                }
                return .none

            case .progressFinished:
                state.isLoading = false
                return .run { send in
                    do {
                        async let payment = offramp.checkpointCurrencyCode()
                        async let topUp = offramp.topUpCheckpointMicros()
                        await send(.checkpointsLoaded(try await payment, try await topUp))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .historyTapped:
                state.historyReturnPage = state.page
                state.page = .history
                state.isLoading = true
                return .run { send in
                    do {
                        await send(.historyLoaded(try await offramp.history()))
                    }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .historyLoaded(let history):
                state.history = history
                state.isLoading = false
                return .none

            case .recoverTapped(let orderId):
                state.page = .progress
                state.progress = []
                state.isLoading = true
                return .run { send in
                    do {
                        let stream = try await offramp.recoverFunds(orderId)
                        for await status in stream { await send(.progressReceived(status)) }
                        await send(.progressFinished)
                    } catch OfframpClientError.authenticationCancelled {
                        await send(.operationCancelled(.history))
                    } catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.operation, cancelInFlight: true)

            case .refundTapped:
                guard state.account?.canRefundToZec == true else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    do { await send(.refundPreviewLoaded(try await offramp.previewRefund())) }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .refundPreviewLoaded(let preview):
                state.bridgePreview = preview
                state.isLoading = false
                state.isRefundConfirmationPresented = true
                return .none

            case .refundConfirmed:
                state.isRefundConfirmationPresented = false
                return .send(.recoverTapped(nil))

            case .refundDismissed:
                state.isRefundConfirmationPresented = false
                state.bridgePreview = nil
                return .none

            case .copyAccountAddressTapped:
                guard let address = state.account?.address else { return .none }
                pasteboard.setString(RedactableString(address))
                state.isAddressCopied = true
                return .none

            case .discardCheckpointTapped:
                state.isCheckpointDiscardConfirmationPresented = true
                return .none

            case .discardCheckpointConfirmed:
                state.isCheckpointDiscardConfirmationPresented = false
                return .run { send in
                    do {
                        try await offramp.discardCheckpoint()
                        await send(.checkpointDiscarded)
                    } catch { await send(.loadFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .discardCheckpointDismissed:
                state.isCheckpointDiscardConfirmationPresented = false
                return .none

            case .checkpointDiscarded:
                state.hasCheckpoint = false
                state.checkpointCurrencyCode = nil
                state.isResumingCheckpoint = false
                return .none

            case .discardTopUpCheckpointTapped:
                state.isTopUpDiscardConfirmationPresented = true
                return .none

            case .discardTopUpCheckpointConfirmed:
                state.isTopUpDiscardConfirmationPresented = false
                return .run { send in
                    do {
                        try await offramp.discardTopUpCheckpoint()
                        await send(.topUpCheckpointDiscarded)
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .discardTopUpCheckpointDismissed:
                state.isTopUpDiscardConfirmationPresented = false
                return .none

            case .topUpCheckpointDiscarded:
                state.hasTopUpCheckpoint = false
                state.topUpCheckpointMicros = nil
                state.topUpAmount = ""
                return .none

            case let .checkpointsLoaded(payment, topUp):
                state.checkpointCurrencyCode = payment
                state.hasCheckpoint = payment != nil
                state.topUpCheckpointMicros = topUp
                state.hasTopUpCheckpoint = topUp != nil
                return .none

            case .operationCancelled(let previousPage):
                state.page = previousPage
                state.isLoading = false
                state.progress = []
                state.errorMessage = OfframpClientError.authenticationCancelled.localizedDescription
                return .none

            case .cancelAll:
                state.isLoading = false
                return .merge(
                    .cancel(id: CancelID.operation),
                    .cancel(id: CancelID.request),
                    .run { _ in await offramp.invalidateSession() }
                )

            case .backTapped:
                switch state.page {
                case .amount:
                    return .send(.delegate(.close))
                case .topUp:
                    state.page = .amount
                    return .none
                case .progress where state.latestProgress?.isTerminal != true:
                    // The checkpoint is persisted before every irreversible transition. Closing
                    // cancels local polling; reopening Pay resumes the same bridge/order.
                    return .send(.delegate(.close))
                case .corridors where state.corridorContext == .payment:
                    state.page = .amount
                    state.draftCurrencyCode = state.selectedCurrencyCode
                    return .none
                case .scanner:
                    return .merge(
                        .cancel(id: CancelID.operation),
                        .cancel(id: CancelID.request),
                        .send(.delegate(.close))
                    )
                case .history where state.historyReturnPage != nil:
                    state.page = state.historyReturnPage ?? .amount
                    state.historyReturnPage = nil
                    state.errorMessage = nil
                    return .none
                case .corridors, .history, .progress:
                    return .send(.delegate(.close))
                }

            case .retryTapped:
                return .send(.onAppear)

            case .delegate(.close):
                return .send(.cancelAll)
            }
        }
    }

    fileprivate static let currencyPreferenceKey = "zapp.offramp.currency"

    private static func sanitizedAmount(_ value: String) -> String {
        var seenSeparator = false
        return value.filter { character in
            if character.isNumber { return true }
            if (character == "." || character == ",") && !seenSeparator {
                seenSeparator = true
                return true
            }
            return false
        }.replacingOccurrences(of: ",", with: ".")
    }

    static func usdcMicros(_ value: String) -> String? {
        guard let decimal = Decimal(string: value), decimal > 0 else { return nil }
        var scaled = decimal * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func hasPositiveAmount(_ value: String) -> Bool {
        guard let decimal = Decimal(string: value) else { return false }
        return decimal > 0
    }

    static func validTopUpMicros(_ value: String) -> String? {
        guard
            let micros = usdcMicros(value),
            let amount = Decimal(string: micros),
            amount <= 100_000_000
        else { return nil }
        return micros
    }

    private static func isAllowedOfframpQuote(_ quote: OfframpQuoteModel) -> Bool {
        guard let micros = Decimal(string: quote.usdcMicros) else { return false }
        return micros > 0 && micros <= 100_000_000
    }

    private static func topUpErrorMessage(_ error: Error) -> String {
        if let error = error as? OfframpBridgeError {
            return error.localizedDescription
        }
        if let error = error as? OfframpClientError {
            return error.localizedDescription
        }
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("swift.string error") ||
            description.localizedCaseInsensitiveContains("operation couldn") {
            return "We couldn't prepare the bridge. Check the amount and your spendable ZEC balance, then try again."
        }
        return description
    }

    private static func isInsufficientBalanceError(_ error: Error) -> Bool {
        guard let bridgeError = error as? OfframpBridgeError else { return false }
        guard case .insufficientSpendableBalance = bridgeError else { return false }
        return true
    }

    private static func usdcDisplay(_ micros: String) -> String {
        guard let decimal = Decimal(string: micros) else { return "" }
        return NSDecimalNumber(decimal: decimal / 1_000_000).stringValue
    }

    private static func fiatTopUpDisplay(usdcAmount: String, sellRate: String?) -> String {
        guard
            let usdc = Decimal(string: usdcAmount),
            let sellRate,
            let rate = Decimal(string: sellRate)
        else { return "" }
        return NSDecimalNumber(decimal: usdc * rate).stringValue
    }
}
