// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

@Reducer
struct Onramp {
    enum Page: Equatable {
        case loading
        case unavailable
        case amount
        case confirmation
        case progress
        case payment
        case convertingToZec
        case completion
        case refundedToBase
        case deliveryNeedsAttention
    }

    enum BaseRefundState: Equatable {
        case hidden
        case available
        case blocked
        case inProgress
        case failedRetry
    }

    @ObservableState
    struct State: Equatable {
        var page: Page = .loading
        var destination: OnrampDestinationModel = .zcash
        var isZecDestinationEnabled = true
        var accountAddress: String?
        var accountExplorerURL: URL?
        var baseBalance: String?
        var baseRefundState: BaseRefundState = .hidden
        var currencyCode: String
        var amount = ""
        var limits: OnrampLimitsModel?
        var quote: OnrampQuoteModel?
        var zecEstimate: OnrampZecEstimateModel?
        var quoteSecondsRemaining: Int?
        var requestID: String?
        var orderID: String?
        var receivedUsdc: String?
        var receivedZec: String?
        var fiatPaid: String?
        var transactionExplorerURL: URL?
        var paymentInstruction: OnrampPaymentInstructionModel?
        var paymentSecondsRemaining: Int?
        var isPaymentAmountUntrusted = false
        var progress: OnrampStatusModel?
        var delivery: OnrampDeliveryModel?
        var errorMessage: String?
        var isRequestingQuote = false
        var isRequestingZecEstimate = false
        var isPlacingOrder = false
        var isConfirmingPaid = false
        var isPaidConfirmationPresented = false
        var isInfoPresented = false
        var isSendBaseBalanceConfirmationPresented = false
        var isSendingBaseBalanceToZec = false
        var baseRefundPreview: OfframpBridgePreview?
        var expiryRecheckedFor: String?
        var deliveryStartedFor: String?
        var isRecheckingOrder = false

        var isPaymentWindowClosed: Bool {
            paymentSecondsRemaining.map { $0 <= 0 } ?? false
        }

        var isPayable: Bool { !isPaymentWindowClosed && !isPaymentAmountUntrusted }

        var isSettledAgainstUser: Bool {
            progress?.kind == .failed || progress?.kind == .cancelled
        }

        /// Only the service may end an order. A local countdown reaching zero is not that answer,
        /// so until one arrives the resume checkpoint is the sole handle on money already sent.
        var isOrderResolved: Bool {
            progress.map(\.isTerminal) ?? true
        }

        var canRetryDelivery: Bool {
            delivery?.kind == .failed && delivery?.retryable == true && delivery?.fundsLocation == .baseAccount
        }

        var canContinue: Bool {
            switch page {
            case .amount:
                guard let amountMicros = Onramp.fiatMicros(amount), let limits else { return false }
                return Onramp.withinLimits(amountMicros, limits: limits) && !isRequestingQuote && !isSendingBaseBalanceToZec
            case .confirmation:
                let estimateReady = destination == .base || zecEstimate != nil
                return quote != nil && estimateReady && !isRequestingZecEstimate && !isPlacingOrder
            default:
                return false
            }
        }

        var qrPayload: String? {
            switch paymentInstruction {
            case .upi(_, let payload), .qr(let payload): return payload
            case .fields, .plain, nil: return nil
            }
        }

        var paymentAddress: String? {
            switch paymentInstruction {
            case .upi(let address, _), .plain(let address): return address
            case .qr(let payload): return payload
            case .fields(let fields): return fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
            case nil: return nil
            }
        }

        var paymentRail: String {
            switch currencyCode.uppercased() {
            case "INR": return "UPI"
            case "BRL": return "PIX"
            case "IDR": return "QRIS"
            case "ARS": return "Mercado Pago"
            case "VEN": return "Pago Móvil"
            case "COP": return "Nequi"
            default: return String(localizable: .onrampPaymentRailBankTransfer)
            }
        }

        var currencySymbol: String {
            switch currencyCode.uppercased() {
            case "INR": return "₹"
            case "BRL": return "R$"
            case "IDR": return "Rp"
            case "ARS": return "$"
            case "VEN": return "Bs."
            case "NGN": return "₦"
            case "COP": return "$"
            default: return currencyCode
            }
        }

        static func initial(currencyCode: String) -> Self {
            Self(currencyCode: currencyCode)
        }
    }

    @Dependency(\.onramp) var onramp
    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var continuousClock
    @Dependency(\.date) var date

    enum CancelID {
        case load
        case account
        case quote
        case driver
        case countdown
        case confirmPaid
        case delivery
        case baseRefund
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard onramp.isConfigured() else {
                    state.page = .unavailable
                    return .none
                }
                state.page = .loading
                state.errorMessage = nil
                let currency = state.currencyCode
                // Two lanes: only the first decides which page to show. The account summary is
                // an on-chain read, and Android does not block on it either.
                return .merge(
                    .run { send in
                        do {
                            async let limits = onramp.limits(currency)
                            async let recipient = onramp.recipientAddress()
                            async let checkpoint = onramp.checkpoint()
                            async let canDeliver = onramp.canDeliverToZec()
                            await send(.loaded(
                                try await limits,
                                try await recipient,
                                try await checkpoint,
                                try await canDeliver
                            ))
                        } catch {
                            await send(.loadFailed(error.localizedDescription))
                        }
                    }
                    .cancellable(id: CancelID.load, cancelInFlight: true),
                    .run { send in
                        await send(.accountSummaryLoaded(try? await offramp.accountSummary()))
                    }
                    .cancellable(id: CancelID.account, cancelInFlight: true)
                )

            // Additive to a page that is already on screen.
            case .accountSummaryLoaded(let account):
                state.accountExplorerURL = account?.explorerURL
                state.baseBalance = account?.balanceDisplay
                state.baseRefundState = Self.baseRefundState(account)
                return .none

            case let .loaded(limits, recipient, checkpoint, canDeliver):
                state.limits = limits
                state.accountAddress = recipient
                state.isZecDestinationEnabled = canDeliver
                if !canDeliver { state.destination = .base }
                if let checkpoint {
                    state.destination = checkpoint.destination
                    state.requestID = checkpoint.id
                    state.orderID = checkpoint.orderID
                    state.page = .loading
                    return .send(.resumeLoadedCheckpoint(checkpoint))
                }
                state.page = limits.enabled && limits.currencyCode.caseInsensitiveCompare(state.currencyCode) == .orderedSame
                    ? .amount
                    : .unavailable
                return .none

            case .resumeLoadedCheckpoint(let checkpoint):
                state.destination = checkpoint.destination
                state.requestID = checkpoint.id
                state.orderID = checkpoint.orderID
                if checkpoint.phase == .completed, checkpoint.destination == .zcash {
                    return deliveryEffect(.resume)
                }
                return statusEffect { try await onramp.resume() }

            case .loadFailed(let message):
                state.page = .unavailable
                state.errorMessage = message
                return .none

            case .amountChanged(let value):
                state.amount = DecimalAmountInput.sanitized(value)
                state.quote = nil
                state.zecEstimate = nil
                state.errorMessage = nil
                return .none

            case .destinationSelected(let destination):
                guard state.page == .amount, !state.isRequestingQuote else { return .none }
                guard destination != .zcash || state.isZecDestinationEnabled else { return .none }
                state.destination = destination
                return .none

            case .continueTapped:
                switch state.page {
                case .amount:
                    guard state.canContinue, let micros = Self.fiatMicros(state.amount) else { return .none }
                    state.isRequestingQuote = true
                    state.errorMessage = nil
                    let currency = state.currencyCode
                    return .run { send in
                        do { await send(.quoteLoaded(try await onramp.quote(micros, currency))) }
                        catch { await send(.quoteFailed(error.localizedDescription)) }
                    }
                    .cancellable(id: CancelID.quote, cancelInFlight: true)

                case .confirmation:
                    guard state.canContinue, let quote = state.quote, !state.isPlacingOrder else { return .none }
                    // Cancelling a collector cannot un-send an order POST that already left. This
                    // state guard prevents a same-frame double tap from placing two BUY orders.
                    state.isPlacingOrder = true
                    state.page = .progress
                    state.progress = nil
                    let destination = state.destination
                    let estimate = state.zecEstimate
                    return .merge(
                        .cancel(id: CancelID.countdown),
                        statusEffect { try await onramp.start(quote, destination, estimate) }
                    )

                default:
                    return .none
                }

            case .quoteLoaded(let quote):
                state.quote = quote
                state.zecEstimate = nil
                state.page = .confirmation
                state.isRequestingQuote = false
                state.errorMessage = nil
                let countdown = quoteCountdown(to: quote.expiresAt)
                guard state.destination == .zcash, let account = state.accountAddress else { return countdown }
                state.isRequestingZecEstimate = true
                return .merge(
                    countdown,
                    .run { send in
                        do { await send(.zecEstimateLoaded(try await onramp.estimateToZec(account, quote.netUsdcMicros))) }
                        catch { await send(.zecEstimateFailed(error.localizedDescription)) }
                    }
                    .cancellable(id: CancelID.quote, cancelInFlight: false)
                )

            case .quoteFailed(let message):
                state.isRequestingQuote = false
                state.errorMessage = message
                return .none

            case .zecEstimateLoaded(let estimate):
                state.zecEstimate = estimate
                state.isRequestingZecEstimate = false
                state.errorMessage = nil
                return .none

            case .zecEstimateFailed:
                state.zecEstimate = nil
                state.isRequestingZecEstimate = false
                state.errorMessage = String(localizable: .onrampErrorZecEstimate)
                return .none

            case .quoteTicked(let seconds):
                state.quoteSecondsRemaining = seconds
                return .none

            case .quoteExpired:
                guard state.page == .confirmation else { return .none }
                state.page = .amount
                return .send(.continueTapped)

            case .statusReceived(let status):
                state.progress = status
                state.isRecheckingOrder = false
                state.requestID = status.id ?? state.requestID
                state.orderID = status.orderID ?? state.orderID
                state.isPlacingOrder = false
                switch status.kind {
                case .awaitingPayment:
                    state.page = .payment
                    state.paymentInstruction = status.instruction
                    state.paymentSecondsRemaining = nil
                    state.isPaidConfirmationPresented = false
                    state.errorMessage = nil
                    let currency = state.currencyCode
                    return .merge(
                        paymentCountdown(status),
                        .run { send in
                            do { await send(.paymentAmountChecked(try await onramp.declaredAmountDisagrees(currency, status))) }
                            catch { await send(.paymentAmountChecked(true)) }
                        }
                    )

                case .completed:
                    state.receivedUsdc = status.netUsdcMicros.map(Self.displayMicros)
                    state.fiatPaid = status.fiatMicros.map(Self.displayMicros)
                    state.paymentInstruction = nil
                    state.paymentSecondsRemaining = nil
                    state.isPaidConfirmationPresented = false
                    if state.destination == .zcash,
                       let requestID = status.id ?? state.requestID,
                       let recipient = status.recipientAddress,
                       let amount = status.netUsdcMicros {
                        state.page = .convertingToZec
                        guard state.deliveryStartedFor != requestID else { return .none }
                        state.deliveryStartedFor = requestID
                        return deliveryEffect(
                            .fresh(orderID: requestID, recipient: recipient, usdcMicros: amount)
                        )
                    }
                    state.page = .completion
                    return transactionURLEffect(status.paidTransactionHash)

                case .failed, .cancelled:
                    state.page = .progress
                    state.paymentInstruction = nil
                    state.paymentSecondsRemaining = nil
                    state.isPaidConfirmationPresented = false
                    state.errorMessage = Self.failureMessage(status.failureCode)
                    return .cancel(id: CancelID.countdown)

                default:
                    state.page = .progress
                    state.paymentInstruction = nil
                    state.paymentSecondsRemaining = nil
                    state.errorMessage = nil
                    return .none
                }

            case .statusStreamFinished:
                state.isPlacingOrder = false
                state.isConfirmingPaid = false
                state.isRecheckingOrder = false
                return .none

            case .authenticationCancelled:
                state.isPlacingOrder = false
                state.isConfirmingPaid = false
                state.isRecheckingOrder = false
                if state.page == .progress, state.orderID == nil, state.quote != nil {
                    state.page = .confirmation
                }
                state.errorMessage = OnrampClientError.authenticationCancelled.localizedDescription
                return .none

            case .statusOperationFailed(let message):
                state.isPlacingOrder = false
                state.isConfirmingPaid = false
                state.isRecheckingOrder = false
                state.errorMessage = message
                guard let orderID = state.orderID else {
                    state.page = state.quote == nil ? .unavailable : .confirmation
                    return .none
                }
                let previous = state.progress
                state.progress = OnrampStatusModel(
                    kind: .failed,
                    phase: previous?.phase ?? .failed,
                    id: previous?.id,
                    orderID: orderID,
                    failureCode: .networkUnavailable,
                    instruction: previous?.instruction,
                    fiatMicros: previous?.fiatMicros,
                    netUsdcMicros: previous?.netUsdcMicros,
                    recipientAddress: previous?.recipientAddress,
                    paidTransactionHash: previous?.paidTransactionHash,
                    expiresAt: previous?.expiresAt,
                    isTerminal: false
                )
                state.page = .progress
                return .none

            case .paymentAmountChecked(let disagrees):
                state.isPaymentAmountUntrusted = disagrees
                if disagrees { state.isPaidConfirmationPresented = false }
                return .none

            case .paidTapped:
                guard state.page == .payment, state.isPayable else { return .none }
                state.isPaidConfirmationPresented = true
                return .none

            case .paidDismissed:
                state.isPaidConfirmationPresented = false
                return .none

            case .paidConfirmed:
                let payable = state.page == .payment && state.isPayable
                state.isPaidConfirmationPresented = false
                guard payable, !state.isConfirmingPaid else { return .none }
                state.isConfirmingPaid = true
                return statusEffect { try await onramp.confirmPaid() }
                    .cancellable(id: CancelID.confirmPaid, cancelInFlight: false)

            case .cancelTapped:
                guard state.progress?.phase == .awaitingMerchant else { return .none }
                return statusEffect { try await onramp.cancel() }

            case .retryTapped:
                if state.progress?.failureCode?.leavesOrderAlive == true {
                    state.errorMessage = nil
                    state.page = .progress
                    return statusEffect { try await onramp.resume() }
                }
                // Discarding the checkpoint here is what makes starting over irreversible, so it
                // waits for the service's own terminal word rather than a lapsed local deadline.
                guard state.isOrderResolved else { return .send(.recheckOrderTapped) }
                state = .initial(currencyCode: state.currencyCode)
                return .merge(
                    cancelEffects(),
                    .run { send in
                        do { try await onramp.clearCheckpoint(); await send(.onAppear) }
                        catch { await send(.loadFailed(error.localizedDescription)) }
                    }
                )

            case .doneTapped:
                return .run { send in
                    try? await onramp.clearCheckpoint()
                    await send(.delegate(.close))
                }

            case .deliveryStatusReceived(let delivery):
                state.delivery = delivery
                switch delivery.kind {
                case .delivered:
                    state.page = .completion
                    state.receivedZec = delivery.outputZec
                    return transactionURLEffect(delivery.baseTransactionHash)
                case .refundedToBase:
                    state.page = .refundedToBase
                    state.receivedUsdc = delivery.refundedUsdcMicros.map(Self.displayMicros)
                case .failed:
                    state.page = .deliveryNeedsAttention
                    state.errorMessage = Self.deliveryFailureMessage(delivery.fundsLocation)
                case .preparing, .submitting, .awaitingZec:
                    state.page = .convertingToZec
                    state.errorMessage = nil
                }
                return .none

            case .deliveryFailed(let delivery):
                state.delivery = delivery
                state.page = .deliveryNeedsAttention
                state.errorMessage = Self.deliveryFailureMessage(delivery.fundsLocation)
                return .none

            case .deliveryStreamFinished:
                return .none

            case .deliveryActionTapped:
                return deliveryEffect(.retry)

            case .copyAccountAddressTapped:
                guard let address = state.accountAddress else { return .none }
                pasteboard.setString(RedactableString(address))
                return .none

            case .copyPaymentAddressTapped:
                guard let address = state.paymentAddress else { return .none }
                pasteboard.setString(RedactableString(address))
                return .none

            case .sendBaseBalanceToZecTapped:
                guard [.available, .failedRetry].contains(state.baseRefundState), !state.isRequestingQuote else { return .none }
                // The bridge only executes a refund it has already quoted, so the preview is what
                // authorizes the send — not merely what the confirmation sheet reads from.
                state.baseRefundState = .inProgress
                state.errorMessage = nil
                return .run { send in
                    do { await send(.baseRefundPreviewLoaded(try await offramp.previewRefund())) }
                    catch { await send(.baseBalanceSendFailed(error.localizedDescription)) }
                }
                .cancellable(id: CancelID.baseRefund, cancelInFlight: true)

            case .baseRefundPreviewLoaded(let preview):
                state.baseRefundPreview = preview
                state.baseRefundState = .available
                state.isSendBaseBalanceConfirmationPresented = true
                return .none

            case .sendBaseBalanceToZecDismissed:
                guard !state.isSendingBaseBalanceToZec else { return .none }
                state.isSendBaseBalanceConfirmationPresented = false
                state.baseRefundPreview = nil
                return .none

            case .sendBaseBalanceToZecConfirmed:
                guard [.available, .failedRetry].contains(state.baseRefundState),
                      !state.isSendingBaseBalanceToZec,
                      state.baseRefundPreview != nil else { return .none }
                state.isSendBaseBalanceConfirmationPresented = false
                state.isSendingBaseBalanceToZec = true
                state.baseRefundState = .inProgress
                return .run { send in
                    do {
                        let stream = try await offramp.recoverFunds(nil)
                        // The bridge reports a failed refund as a terminal status, not as a thrown
                        // error, so a stream that ends without a successful one moved no money.
                        var terminal: OfframpProgressModel?
                        for await status in stream where status.isTerminal { terminal = status }
                        guard let terminal, terminal.isSuccess else {
                            await send(.baseBalanceSendFailed(String(localizable: .onrampSendToZecFailed)))
                            return
                        }
                        await send(.baseBalanceSent)
                    } catch OfframpClientError.authenticationCancelled {
                        await send(.baseBalanceSendCancelled)
                    } catch {
                        await send(.baseBalanceSendFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.baseRefund, cancelInFlight: false)

            case .baseBalanceSent:
                state.isSendingBaseBalanceToZec = false
                state.baseRefundPreview = nil
                state.baseBalance = nil
                state.baseRefundState = .hidden
                return .none

            case .baseBalanceSendFailed(let message):
                state.isSendingBaseBalanceToZec = false
                state.isSendBaseBalanceConfirmationPresented = false
                state.baseRefundPreview = nil
                state.baseRefundState = .failedRetry
                state.errorMessage = message
                return .none

            case .baseBalanceSendCancelled:
                state.isSendingBaseBalanceToZec = false
                state.isSendBaseBalanceConfirmationPresented = false
                state.baseRefundPreview = nil
                state.baseRefundState = .available
                return .none

            case .transactionURLLoaded(let url):
                state.transactionExplorerURL = url
                return .none

            case .paymentTicked(let seconds):
                state.paymentSecondsRemaining = seconds
                return .none

            case .paymentWindowExpired(let orderID):
                guard state.expiryRecheckedFor != orderID else { return .none }
                state.expiryRecheckedFor = orderID
                return .send(.recheckOrderTapped)

            case .recheckOrderTapped:
                guard !state.isRecheckingOrder else { return .none }
                state.isRecheckingOrder = true
                state.errorMessage = nil
                return statusEffect { try await onramp.resume() }

            case .infoTapped:
                state.isInfoPresented = true
                return .none

            case .infoDismissed:
                state.isInfoPresented = false
                return .none

            case .backTapped:
                guard !state.isSendingBaseBalanceToZec else { return .none }
                if state.page == .confirmation {
                    state.page = .amount
                    state.quote = nil
                    state.zecEstimate = nil
                    state.quoteSecondsRemaining = nil
                    state.isRequestingQuote = false
                    state.isRequestingZecEstimate = false
                    state.errorMessage = nil
                    return .merge(.cancel(id: CancelID.quote), .cancel(id: CancelID.countdown))
                }
                return .send(.delegate(.close))

            case .cancelAll:
                state.isPaidConfirmationPresented = false
                state.isInfoPresented = false
                return cancelEffects()

            case .delegate:
                return .none
            }
        }
    }

}
