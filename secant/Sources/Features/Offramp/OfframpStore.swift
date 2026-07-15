// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

@Reducer
struct Offramp {
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
        var checkpointCurrencyCode: String?
        var isResumingCheckpoint = false
        var account: OfframpAccountModel?
        var isAddressCopied = false
        var isRefundConfirmationPresented = false

        var selectedCorridor: OfframpCorridor? {
            corridors.first { $0.currencyCode == selectedCurrencyCode }
        }

        var draftCorridor: OfframpCorridor? {
            corridors.first { $0.currencyCode == draftCurrencyCode }
        }

        var latestProgress: OfframpProgressModel? { progress.last }

        init(page: Page = .scanner) {
            let saved = UserDefaults.standard.string(forKey: Offramp.currencyPreferenceKey) ?? "INR"
            self.page = page
            self.selectedCurrencyCode = saved
            self.draftCurrencyCode = saved
        }

        static func initial(page: Page = .scanner) -> Self { Self(page: page) }
    }

    enum Action: Equatable {
        case onAppear
        case loadedCorridors([OfframpCorridor], String?)
        case loadFailed(String)
        case accountLoaded(OfframpAccountModel)
        case draftCorridorTapped(String)
        case saveCorridorTapped
        case resumeCheckpointTapped
        case scanPayload(String)
        case scanParsed(OfframpScanResult)
        case scanFailed(String)
        case fiatAmountChanged(String)
        case quoteTapped
        case quoteLoaded(OfframpQuoteModel)
        case payTapped
        case addFundsTapped
        case startTopUpTapped
        case progressReceived(OfframpProgressModel)
        case progressFinished
        case historyTapped
        case historyLoaded([OfframpHistoryModel])
        case recoverTapped(String?)
        case refundTapped
        case refundConfirmed
        case refundDismissed
        case copyAccountAddressTapped
        case discardCheckpointTapped
        case checkpointDiscarded
        case backTapped
        case retryTapped
        case delegate(Delegate)

        enum Delegate: Equatable { case close }
    }

    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard

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
                        await send(.loadedCorridors(try await corridors, try await checkpointCurrency))
                        if page == .history {
                            async let history = offramp.history()
                            async let account = offramp.accountSummary()
                            await send(.historyLoaded(try await history))
                            await send(.accountLoaded(try await account))
                        } else if page == .corridors {
                            await send(.accountLoaded(try await offramp.accountSummary()))
                        }
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }

            case let .loadedCorridors(corridors, checkpointCurrency):
                state.corridors = corridors
                state.checkpointCurrencyCode = checkpointCurrency
                state.hasCheckpoint = checkpointCurrency != nil
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
                return .none

            case .draftCorridorTapped(let code):
                state.draftCurrencyCode = code
                return .none

            case .saveCorridorTapped:
                state.selectedCurrencyCode = state.draftCurrencyCode
                UserDefaults.standard.set(state.selectedCurrencyCode, forKey: Self.currencyPreferenceKey)
                return .send(.delegate(.close))

            case .resumeCheckpointTapped:
                guard let currency = state.checkpointCurrencyCode else { return .none }
                state.selectedCurrencyCode = currency
                state.draftCurrencyCode = currency
                state.isResumingCheckpoint = true
                state.errorMessage = nil
                return .none

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

            case .scanParsed(let scan):
                state.scan = scan
                state.fiatAmount = scan.fiatAmount ?? ""
                state.quote = nil
                state.page = .amount
                state.isLoading = false
                return .none

            case .fiatAmountChanged(let value):
                state.fiatAmount = Self.sanitizedAmount(value)
                state.quote = nil
                return .none

            case .quoteTapped:
                guard !state.fiatAmount.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                let currency = state.selectedCurrencyCode
                let amount = state.fiatAmount
                return .run { send in
                    do { await send(.quoteLoaded(try await offramp.quote(currency, amount))) }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }

            case .quoteLoaded(let quote):
                state.quote = quote
                state.isLoading = false
                return .none

            case .payTapped:
                guard let quote = state.quote, let scan = state.scan, !state.isLoading else { return .none }
                state.page = .progress
                state.progress = []
                state.isLoading = true
                return .run { send in
                    do {
                        let stream = try await offramp.pay(quote, scan, nil)
                        for await status in stream { await send(.progressReceived(status)) }
                        await send(.progressFinished)
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }

            case .addFundsTapped:
                guard state.quote != nil else { return .none }
                state.page = .topUp
                state.isLoading = true
                return .run { send in
                    do { await send(.accountLoaded(try await offramp.accountSummary())) }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }

            case .startTopUpTapped:
                guard let quote = state.quote, quote.shortfallMicros != "0", !state.isLoading else { return .none }
                state.page = .progress
                state.progress = []
                state.isLoading = true
                return .run { send in
                    do {
                        let stream = try await offramp.bridgeToBase(quote.shortfallMicros, nil)
                        for await status in stream { await send(.progressReceived(status)) }
                        await send(.progressFinished)
                    } catch { await send(.loadFailed(error.localizedDescription)) }
                }

            case .progressReceived(let status):
                if state.progress.last?.kind == status.kind {
                    state.progress[state.progress.count - 1] = status
                } else {
                    state.progress.append(status)
                }
                state.isLoading = !status.isTerminal
                if status.isTerminal {
                    state.hasCheckpoint = false
                    state.checkpointCurrencyCode = nil
                    state.isResumingCheckpoint = false
                }
                return .none

            case .progressFinished:
                state.isLoading = false
                return .none

            case .historyTapped:
                state.page = .history
                state.isLoading = true
                return .run { send in
                    do {
                        async let history = offramp.history()
                        async let account = offramp.accountSummary()
                        await send(.historyLoaded(try await history))
                        await send(.accountLoaded(try await account))
                    }
                    catch { await send(.loadFailed(error.localizedDescription)) }
                }

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
                    } catch { await send(.loadFailed(error.localizedDescription)) }
                }

            case .refundTapped:
                guard state.account?.canRefundToZec == true else { return .none }
                state.isRefundConfirmationPresented = true
                return .none

            case .refundConfirmed:
                state.isRefundConfirmationPresented = false
                return .send(.recoverTapped(nil))

            case .refundDismissed:
                state.isRefundConfirmationPresented = false
                return .none

            case .copyAccountAddressTapped:
                guard let address = state.account?.address else { return .none }
                pasteboard.setString(RedactableString(address))
                state.isAddressCopied = true
                return .none

            case .discardCheckpointTapped:
                return .run { send in
                    do {
                        try await offramp.discardCheckpoint()
                        await send(.checkpointDiscarded)
                    } catch { await send(.loadFailed(error.localizedDescription)) }
                }

            case .checkpointDiscarded:
                state.hasCheckpoint = false
                state.checkpointCurrencyCode = nil
                state.isResumingCheckpoint = false
                return .none

            case .backTapped:
                switch state.page {
                case .amount:
                    state.page = .scanner
                    state.scan = nil
                    state.quote = nil
                    return .none
                case .topUp:
                    state.page = .amount
                    return .none
                case .progress where state.latestProgress?.isTerminal != true:
                    // The checkpoint is persisted before every irreversible transition. Closing
                    // cancels local polling; reopening Pay resumes the same bridge/order.
                    return .send(.delegate(.close))
                case .corridors, .scanner, .history, .progress:
                    return .send(.delegate(.close))
                }

            case .retryTapped:
                return .send(.onAppear)

            case .delegate:
                return .none
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
}
