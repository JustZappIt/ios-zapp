//
//  SendCoordFlowCoordinator.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-03-18.
//

import Foundation
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension SendCoordFlow {
    func coordinatorReduce() -> Reduce<SendCoordFlow.State, SendCoordFlow.Action> {
        Reduce { state, action in
            switch action {
                // MARK: - Unified asset selector

                // Android: `onAssetPickerClick` → `SwapAssetPickerArgs`. iOS presents it as a sheet
                // over the same screen so the form is never left.
            case .assetPickerRequested:
                state.isAssetPickerPresented = true
                state.swapState.searchTerm = ""
                return .send(.swap(.updateAssetsAccordingToSearchTerm))

            case .assetPickerDismissed:
                state.isAssetPickerPresented = false
                return .none

                // Android's `onAmountSwap`; swap mode has its own equivalent
                // (`SwapAndPay.switchInputTapped`).
            case .amountInputSwapped:
                guard state.mode == .zec else { return .none }
                state.isFiatPrimary.toggle()
                return .none

                // Android clears the recipient whenever the selected asset's id changes
                // (`UnifiedSendVM` init, `selectedAsset.drop(1)`), because an address for one chain
                // is meaningless on another. The ZEC-denominated amount is deliberately kept.
            case .zecAssetSelected:
                state.isAssetPickerPresented = false
                guard state.mode != .zec else { return .none }
                state.mode = .zec
                let carriedAmount = state.swapState.isInputInUsd ? "" : state.swapState.amountText
                state.swapState.address = ""
                state.swapState.selectedContact = nil
                state.swapState.isNotAddressInAddressBook = false
                state.swapState.isAddressBookHintVisible = false
                state.isFiatPrimary = false
                return .merge(
                    .send(.sendForm(.addressUpdated(.empty))),
                    .send(.sendForm(.zecAmountUpdated(carriedAmount.redacted)))
                )

            case .swapAssetSelected(let asset):
                state.isAssetPickerPresented = false
                let wasZec = state.mode == .zec
                state.mode = .swap
                // The unified screen only ever runs Android's EXACT_INPUT swap (spend ZEC, receive
                // the picked asset). Swap-to-ZEC lives in `SwapAndPayCoordFlow`.
                state.swapState.isSwapExperienceEnabled = true
                state.swapState.isSwapToZecExperienceEnabled = false
                state.swapState.address = ""
                state.swapState.selectedContact = nil
                state.swapState.isNotAddressInAddressBook = false
                state.swapState.isAddressBookHintVisible = false
                if wasZec {
                    state.swapState.isInputInUsd = false
                    state.swapState.amountText = state.sendFormState.zecAmountText.data
                    return .merge(
                        .send(.sendForm(.addressUpdated(.empty))),
                        .send(.swap(.assetTapped(asset)))
                    )
                }
                return .send(.swap(.assetTapped(asset)))

                // MARK: - Unified back / Top Up / deposit

                // Android's `onBack`: a quote request in flight asks before throwing it away.
            case .backButtonTapped:
                if state.mode == .swap && state.swapState.isQuoteRequestInFlight {
                    return .send(.swap(.backButtonTapped(true)))
                }
                return .send(.sendForm(.dismissRequired))

                // `SwapAndPay` reports "leave the flow" through `customBackRequired`; the unified
                // form funnels it into the same dismissal Root already listens for.
            case .swap(.customBackRequired):
                return .send(.sendForm(.dismissRequired))

                // Delegates handled by Root.
            case .topUpRequested, .swapToZecRequested:
                return .none

                // MARK: - Address Book

            case let .path(.element(id: _, action: .addressBook(.editId(address, id)))):
                state.path.removeAll()
                audioServices.systemSoundVibrate()
                if state.mode == .swap {
                    return .send(.swap(.addressBookContactSelected(id)))
                }
                return .send(.sendForm(.addressUpdated(address.redacted)))

            case .path(.element(id: _, action: .addressBook(.walletAccountTapped(let contact)))):
                if let address = contact.unifiedAddress, state.mode == .zec {
                    state.path.removeAll()
                    audioServices.systemSoundVibrate()
                    return .send(.sendForm(.addressUpdated(address.redacted)))
                }
                return .none

            case .path(.element(id: _, action: .addressBook(.addManualButtonTapped))):
                var addressBookState = AddressBook.State.initial
                addressBookState.isAddressFocused = true
                addressBookState.context = state.mode == .swap ? .swap : .send
                state.path.append(.addressBookContact(addressBookState))
                return .none

            case .path(.element(id: _, action: .addressBook(.scanButtonTapped))):
                var scanState = Scan.State.initial
                scanState.checkers = state.mode == .swap ? [.swapStringScanChecker] : [.zcashAddressScanChecker]
                state.path.append(.scan(scanState))
                return .none

                // MARK: - Address Book Contact

            case .path(.element(id: _, action: .addressBookContact(.dismissAddContactRequired))):
                let _ = state.path.popLast()

                // handling the path in the transaction details
                for element in state.path {
                    if element.is(\.transactionDetails) {
                        return .none
                    }
                }

                // handling the path in send confirmation
                for element in state.path {
                    if element.is(\.sendConfirmation) {
                        return .none
                    }
                }

                // handling the path in send form
                for element in state.path {
                    if element.is(\.scan) {
                        let _ = state.path.popLast()
                        return .none
                    }
                }
                if state.mode == .swap {
                    return .send(.swap(.checkSelectedContact))
                }
                return .none

                // MARK: - Keystone

            case .path(.element(id: _, action: .sendConfirmation(.confirmWithKeystoneTapped))):
                for element in state.path {
                    if case .sendConfirmation(let sendConfirmationState) = element {
                        state.path.append(.confirmWithKeystone(sendConfirmationState))
                        if let last = state.path.ids.last {
                            return .send(.path(.element(id: last, action: .confirmWithKeystone(.resolvePCZT))))
                        }
                    }
                }
                return .none

            case .path(.element(id: _, action: .requestZecConfirmation(.confirmWithKeystoneTapped))):
                for element in state.path {
                    if case .requestZecConfirmation(let sendConfirmationState) = element {
                        state.path.append(.confirmWithKeystone(sendConfirmationState))
                        if let last = state.path.ids.last {
                            return .send(.path(.element(id: last, action: .confirmWithKeystone(.resolvePCZT))))
                        }
                    }
                }
                return .none

            case .path(.element(id: _, action: .confirmWithKeystone(.getSignatureTapped))):
                var scanState = Scan.State.initial
                scanState.checkers = [.keystonePCZTScanChecker]
                state.path.append(.scan(scanState))
                return .none

            case .path(.element(id: _, action: .scan(.foundPCZT(let pcztWithSigs)))):
                for (id, element) in zip(state.path.ids, state.path) {
                    if case .confirmWithKeystone(let sendConfirmationState) = element {
                        // A swap has to be recorded before the signed PCZT is submitted, exactly as
                        // `SwapAndPayCoordFlow` does — the deposit address is what links the
                        // broadcast transaction to the swap in transaction history.
                        if state.mode == .swap {
                            markSwapTransaction(&state, address: sendConfirmationState.address)
                        }
                        state.path.append(.sending(sendConfirmationState))
                        return .send(.path(.element(id: id, action: .confirmWithKeystone(.foundPCZT(pcztWithSigs)))))
                    }
                }
                return .none

            case .path(.element(id: _, action: .confirmWithKeystone(.updateResult(let result)))):
                for element in state.path {
                    if case .confirmWithKeystone(let sendConfirmationState) = element {
                        return .send(.resolveSendResult(result, sendConfirmationState))
                    }
                }
                return .none

            case .path(.element(id: _, action: .confirmWithKeystone(.pcztSendFailed(let error)))):
                for element in state.path.reversed() {
                    if element.is(\.sending) {
                        for (id, element2) in zip(state.path.ids, state.path) {
                            if element2.is(\.confirmWithKeystone) {
                                return .send(.path(.element(id: id, action: .confirmWithKeystone(.sendFailed(error?.toZcashError(), true)))))
                            }
                        }
                        break
                    } else if element.is(\.scan) || element.is(\.confirmWithKeystone) {
                        for element2 in state.path {
                            if case .confirmWithKeystone(let sendConfirmationState) = element2 {
                                state.path.append(.preSendingFailure(sendConfirmationState))
                            }
                        }
                        break
                    }
                }
                return .none

                // MARK: - Request ZEC Confirmation

            case .path(.element(id: _, action: .requestZecConfirmation(.goBackTappedFromRequestZec))):
                state.path.removeAll()
                return .none

            case .path(.element(id: _, action: .requestZecConfirmation(.sendRequested))):
                for element in state.path {
                    if case .requestZecConfirmation(let sendConfirmationState) = element {
                        state.path.append(.sending(sendConfirmationState))
                        break
                    }
                }
                return .none

            case .path(.element(id: _, action: .requestZecConfirmation(.sendFailed))):
                state.path.removeAll()
                return .none

            case .path(.element(id: _, action: .requestZecConfirmation(.saveAddressTapped(let address)))):
                var addressBookState = AddressBook.State.initial
                addressBookState.isNameFocused = true
                addressBookState.address = address.data
                addressBookState.isValidZcashAddress = true
                addressBookState.context = .send
                state.path.append(.addressBookContact(addressBookState))
                return .none

            case .path(.element(id: _, action: .requestZecConfirmation(.updateResult(let result)))):
                for element in state.path {
                    if case .requestZecConfirmation(let sendConfirmationState) = element {
                        return .send(.resolveSendResult(result, sendConfirmationState))
                    }
                }
                return .none

                // MARK: - Scan

            case .path(.element(id: _, action: .scan(.foundAddress(let address)))):
                // Handling of scan inside address book
                for element in state.path {
                    if element.is(\.addressBook) {
                        var addressBookState = AddressBook.State.initial
                        addressBookState.address = address.data
                        addressBookState.isValidZcashAddress = true
                        addressBookState.isNameFocused = true
                        addressBookState.context = .send
                        state.path.append(.addressBookContact(addressBookState))
                        audioServices.systemSoundVibrate()
                        return .none
                    }
                }
                // handling of scan for the send form
                let _ = state.path.popLast()
                audioServices.systemSoundVibrate()
                return .send(.sendForm(.addressUpdated(address)))

                // Swap mode scans a raw destination string (any chain), not a Zcash address.
            case .path(.element(id: _, action: .scan(.foundString(let address)))):
                audioServices.systemSoundVibrate()
                if state.path.contains(where: { $0.is(\.addressBook) }) {
                    var addressBookState = AddressBook.State.initial
                    addressBookState.address = address
                    addressBookState.isNameFocused = true
                    addressBookState.context = .swap
                    state.path.append(.addressBookContact(addressBookState))
                    return .none
                }
                _ = state.path.popLast()
                state.swapState.address = address
                return .none

            case .path(.element(id: _, action: .scan(.foundRequestZec(let requestPayment)))):
                let _ = state.path.popLast()
                return .send(.sendForm(.requestZec(requestPayment)))

            case .path(.element(id: _, action: .scan(.cancelTapped))):
                let _ = state.path.popLast()
                return .none

                // MARK: - Send (ZEC-direct mode)

            case .sendForm(.addressBookTapped), .swap(.addressBookTapped):
                var addressBookState = AddressBook.State.initial
                addressBookState.isInSelectMode = true
                addressBookState.context = state.mode == .swap ? .swap : .send
                state.path.append(.addressBook(addressBookState))
                return .none

            case .sendForm(.addNewContactTapped(let address)):
                var addressBookState = AddressBook.State.initial
                addressBookState.isNameFocused = true
                addressBookState.address = address.data
                addressBookState.isValidZcashAddress = true
                addressBookState.context = .send
                state.path.append(.addressBookContact(addressBookState))
                return .none

            case .swap(.notInAddressBookButtonTapped(let address)):
                var addressBookState = AddressBook.State.initial
                addressBookState.isNameFocused = true
                addressBookState.address = address
                addressBookState.context = .swap
                state.path.append(.addressBookContact(addressBookState))
                return .none

                // Android gates the in-form scanner's ZIP-321 handling on
                // `UnifiedSendArgs.isScanZip321Enabled`; with it off the scanner can only yield a
                // plain address.
            case .sendForm(.scanTapped):
                var scanState = Scan.State.initial
                scanState.checkers = state.isScanZip321Enabled
                    ? [.zcashAddressScanChecker, .requestZecScanChecker]
                    : [.zcashAddressScanChecker]
                state.path.append(.scan(scanState))
                return .none

            case .swap(.scanTapped):
                var scanState = Scan.State.initial
                scanState.checkers = [.swapStringScanChecker]
                state.path.append(.scan(scanState))
                return .none

            case .sendForm(.confirmationRequired(let confirmationType)):
                var sendConfirmationState = SendConfirmation.State.initial
                sendConfirmationState.amount = state.sendFormState.amount
                sendConfirmationState.address = state.sendFormState.address.data
                sendConfirmationState.proposal = state.sendFormState.proposal
                sendConfirmationState.feeRequired = state.sendFormState.feeRequired
                sendConfirmationState.message = state.sendFormState.message
                let currencyAmount = state.sendFormState.currencyConversion?.convert(state.sendFormState.amount).redacted ?? .empty
                sendConfirmationState.currencyAmount = currencyAmount

                if confirmationType == .send {
                    state.path.append(.sendConfirmation(sendConfirmationState))
                } else if confirmationType == .requestPayment {
                    state.path.append(.requestZecConfirmation(sendConfirmationState))
                }
                return .none

            case let .sendForm(.sendFailed(_, confirmationType)):
                if confirmationType == .requestPayment {
                    state.path.removeAll()
                }
                return .none

                // MARK: - Swap mode submission

                // Android's swap CTA hands the quote to the shared review/submit machinery. iOS
                // does the same by pushing `SendConfirmation` in `sending` mode and letting it run
                // its own broadcast: `SendConfirmation.sendTriggered` is the single call site of the
                // guarded `sdkSynchronizer.createAndSubmitProposedTransactions`, so swap and
                // ZEC-direct sends share one guarded path and nothing here nests the guard.
                // App-lock first, exactly as `SwapAndPayCoordFlow` does: the sending screen is only
                // pushed once the user has actually authorised, so cancelling Face ID / the PIN
                // leaves them on the form instead of stranded on a progress screen.
            case .swap(.confirmButtonTapped):
                guard state.swapState.proposal != nil, state.swapState.quote != nil, !state.isSwapSubmissionInFlight else {
                    return .none
                }
                return .run { send in
                    guard await localAuthentication.authenticate() else {
                        return
                    }

                    await send(.swapSendAuthorized)
                }

                // Re-checked after the app-lock round trip: two taps can each pass the check above
                // and each authorise, and only this push actually starts a broadcast.
            case .swapSendAuthorized:
                guard
                    let proposal = state.swapState.proposal,
                    let quote = state.swapState.quote,
                    !state.isSwapSubmissionInFlight
                else {
                    return .none
                }
                let depositAddress = quote.depositAddress.isEmpty ? state.swapState.address : quote.depositAddress
                markSwapTransaction(&state, address: depositAddress)
                var sendConfirmationState = SendConfirmation.State.initial
                sendConfirmationState.address = depositAddress
                sendConfirmationState.amount = Zatoshi(NSDecimalNumber(decimal: quote.amountIn).int64Value)
                sendConfirmationState.feeRequired = proposal.totalFeeRequired()
                sendConfirmationState.proposal = proposal
                sendConfirmationState.type = .swap
                state.path.append(.sending(sendConfirmationState))
                guard let last = state.path.ids.last else { return .none }
                // `sendRequested` (not `sendTapped`) — the app-lock check above already happened, and
                // `SendConfirmation` owns everything from here: it is what calls the guarded
                // `createAndSubmitProposedTransactions`.
                return .send(.path(.element(id: last, action: .sending(.sendRequested))))

            case .swap(.confirmWithKeystoneTapped):
                guard let proposal = state.swapState.proposal, !state.isSwapSubmissionInFlight else {
                    return .none
                }
                let keystoneAddress = state.swapState.quote?.depositAddress ?? state.swapState.address
                var sendConfirmationState = SendConfirmation.State.initial
                sendConfirmationState.address = keystoneAddress
                sendConfirmationState.amount = Zatoshi(
                    NSDecimalNumber(decimal: state.swapState.quote?.amountIn ?? 0).int64Value
                )
                sendConfirmationState.feeRequired = proposal.totalFeeRequired()
                sendConfirmationState.proposal = proposal
                sendConfirmationState.type = .swap
                state.path.append(.confirmWithKeystone(sendConfirmationState))
                if let last = state.path.ids.last {
                    return .send(.path(.element(id: last, action: .confirmWithKeystone(.resolvePCZT))))
                }
                return .none

                // Swap mode is the only mode whose `sending` element runs the broadcast itself; in
                // ZEC-direct mode the `sending` element is a presentation copy and the result comes
                // from `sendConfirmation` / `requestZecConfirmation` instead.
            case .path(.element(id: _, action: .sending(.updateResult(let result)))):
                guard state.mode == .swap else { return .none }
                for element in state.path.reversed() {
                    if case .sending(let sendConfirmationState) = element {
                        return .send(.resolveSendResult(result, sendConfirmationState))
                    }
                }
                return .none

                // MARK: - Send Confirmation

            case .path(.element(id: _, action: .sendConfirmation(.cancelTapped))):
                let _ = state.path.popLast()
                return .none

            case .path(.element(id: _, action: .sendConfirmation(.sendRequested))):
                for element in state.path {
                    if case .sendConfirmation(let sendConfirmationState) = element {
                        state.path.append(.sending(sendConfirmationState))
                        break
                    }
                }
                return .none

            case .path(.element(id: _, action: .sendConfirmation(.updateResult(let result)))):
                for element in state.path {
                    if case .sendConfirmation(let sendConfirmationState) = element {
                        return .send(.resolveSendResult(result, sendConfirmationState))
                    }
                }
                return .none

            case .path(.element(id: _, action: .preSendingFailure(.backFromPCZTFailureTapped))):
                state.path.removeAll()
                return .none

            case .path(.element(id: _, action: .sendResultSuccess(.viewTransactionTapped))),
                    .path(.element(id: _, action: .sendResultFailure(.viewTransactionTapped))),
                    .path(.element(id: _, action: .sendResultPending(.viewTransactionTapped))):
                for element in state.path.reversed() {
                    if case .sendConfirmation(let sendConfirmationState) = element {
                        return .send(.viewTransactionRequested(sendConfirmationState))
                    } else if case .requestZecConfirmation(let sendConfirmationState) = element {
                        return .send(.viewTransactionRequested(sendConfirmationState))
                    } else if case .confirmWithKeystone(let sendConfirmationState) = element {
                        return .send(.viewTransactionRequested(sendConfirmationState))
                    } else if case .sending(let sendConfirmationState) = element, state.mode == .swap {
                        return .send(.viewTransactionRequested(sendConfirmationState))
                    }
                }
                return .none

                // MARK: - Self

            case .backToHomeTapped:
                return .none

            case let .resolveSendResult(result, sendConfirmationState):
                switch result {
                case .failure:
                    state.path.append(.sendResultFailure(sendConfirmationState))
                case .pending:
                    state.path.append(.sendResultPending(sendConfirmationState))
                case .success:
                    state.path.append(.sendResultSuccess(sendConfirmationState))
                default: break
                }
                // Best-effort nudge to the swap provider so it starts watching for the deposit —
                // an ordinary HTTPS call, never guarded, and only after the broadcast has already
                // finished and released the transaction guard.
                let isSwapSuccess = state.mode == .swap && result == .success
                if isSwapSuccess, let txId = sendConfirmationState.txIdToExpand, !txId.isEmpty {
                    let depositAddress = sendConfirmationState.address
                    return .run { _ in
                        try? await swapAndPay.submitDepositTxId(txId, depositAddress)
                    }
                }
                return .none

            case .viewTransactionRequested(let sendConfirmationState):
                if let txid = sendConfirmationState.txIdToExpand {
                    var transactionDetailsState = TransactionDetails.State.initial
                    if let index = state.transactions.index(id: txid) {
                        transactionDetailsState.transaction = state.transactions[index]
                    } else {
                        transactionDetailsState.transaction = TransactionState(
                            pendingSendId: txid,
                            zecAmount: sendConfirmationState.amount
                        )
                    }
                    transactionDetailsState.isCloseButtonRequired = true
                    state.path.append(.transactionDetails(transactionDetailsState))
                }
                return .none

                // MARK: - Transaction Details

            case .path(.element(id: _, action: .transactionDetails(.saveAddressTapped))):
                var addressBookState = AddressBook.State.initial
                addressBookState.address = state.sendFormState.address.data
                addressBookState.isNameFocused = true
                addressBookState.isValidZcashAddress = true
                addressBookState.context = .send
                state.path.append(.addressBookContact(addressBookState))
                return .none

            case .path(.element(id: _, action: .transactionDetails(.sendAgainTapped))):
                state.path.removeAll()
                return .none

            default: return .none
            }
        }
    }

    /// Records the pending swap against the transaction that is about to be broadcast, mirroring
    /// `SwapAndPayCoordFlow`'s `swapRequested`. `exactInput` is always `true` here: the unified
    /// screen only runs Android's EXACT_INPUT swap (spend ZEC, receive the picked asset).
    private func markSwapTransaction(_ state: inout State, address: String) {
        guard let provider = state.swapState.selectedAsset?.provider else {
            return
        }
        userMetadataProvider.markTransactionAsSwapFor(
            address,
            provider,
            state.swapState.totalFees,
            state.swapState.totalUSDFees,
            state.swapState.zecAsset?.id ?? "",
            state.swapState.selectedAsset?.id ?? "",
            true,
            SwapConstants.pendingDeposit,
            state.swapState.zecToBeSpendInQuoteUSFormat
        )
        if let account = state.swapState.selectedWalletAccount?.account {
            try? userMetadataProvider.store(account)
        }
    }
}
