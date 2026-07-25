//
//  RootCoordinator.swift
//  Zashi
//
//  Created by Lukáš Korba on 07.03.2025.
//

import Combine
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension Root {
    func coordinatorReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
                
                // MARK: - Returns to Home

            case .settings(.backToHomeTapped),
                .chatContactsList(.backToHomeTapped),
                .chatProfile(.backToHomeTapped),
                .chatRoom(.backToHomeTapped),
                .groupInfo(.backToHomeTapped),
                .newChat(.backToHomeTapped),
                .offramp(.delegate(.close)),
                .receive(.backToHomeTapped),
                .walletBackupCoordFlow(.backToHomeTapped),
                .torSetup(.backToHomeTapped),
                .currencyConversionSetup(.backToHomeTapped),
                .backToHomeFromChatPrivacyTapped,
                .backToHomeFromServerSwitchTapped:
                state.path = nil
                return .none
                
                // MARK: - Accounts

            case .home(.walletAccountTapped(let walletAccount)):
                guard state.selectedWalletAccount != walletAccount else {
                    return .none
                }
                state.$selectedWalletAccount.withLock { $0 = walletAccount }
                state.homeState.transactionListState.isInvalidated = true
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.offramp(.cancelAll)),
                    .send(.home(.smartBanner(.walletAccountChanged))),
                    .send(.home(.walletBalances(.updateBalances))),
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount),
                    // SECURITY (MOB-1352): end any open Flexa session bound to the previous account so a
                    // pending Flexa transaction request can't bind to the newly-selected account.
                    .cancel(id: state.CancelFlexaId)
                )

                // MARK: - Add Keystone HW Wallet Coord Flow

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .restoreInfo(.gotItTapped)))):
                var leavesScreenOpenMutable = false
                for element in state.addKeystoneHWWalletCoordFlowState.path {
                    if case .restoreInfo(let restoreInfoState) = element {
                        leavesScreenOpenMutable = restoreInfoState.isAcknowledged
                    }
                }
                let leavesScreenOpen = leavesScreenOpenMutable
                userDefaults.setValue(leavesScreenOpen, Constants.udLeavesScreenOpen)
                return .run { _ in await autolockHandler.value(leavesScreenOpen) }

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .accountHWWalletSelection(.forgetThisDeviceTapped)))),
                .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .keystoneDeviceReady(.forgetThisDeviceTapped)))):
                state.path = nil
                return .none

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .accountHWWalletSelection(.accountImportSucceeded)))):
                state.path = nil
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .keystoneConnected(.closeTapped)))):
                state.path = nil
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )
                
            case .addKeystoneHWWalletCoordFlow(.addKeystoneHWWallet(.backToHomeTapped)):
                state.path = nil
                return .none

                // MARK: - Add Keystone HW Wallet from Settings

            case .settings(.path(.element(id: _, action: .accountHWWalletSelection(.accountImportSucceeded)))):
                state.path = nil
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )
                
                // MARK: - Resync Wallet

            case .settings(.resyncFinished):
                guard let birthday = state.settingsState.resyncBirthday else {
                    return .none
                }
                var leavesScreenOpen = false
                for element in state.settingsState.path {
                    if case .resyncRestoreInfo(let restoreInfoState) = element {
                        leavesScreenOpen = restoreInfoState.isAcknowledged
                    }
                }
                userDefaults.setValue(leavesScreenOpen, Constants.udLeavesScreenOpen)
                state.path = nil
                state.isRestoringWallet = true
                userDefaults.setValue(true, Constants.udIsResyncingWallet)
                state.$walletStatus.withLock { $0 = .resyncing }
                let leavesScreenOpenFixed = leavesScreenOpen
                return .concatenate(
                    .run { _ in
                        await autolockHandler.value(leavesScreenOpenFixed)
                    },
                    .publisher {
                        sdkSynchronizer.rewind(.height(blockheight: birthday))
                            .replaceEmpty(with: Void())
                            .map { _ in
                                Root.Action.rewindDone(nil)
                            }
                            .catch { error in
                                Just(Root.Action.rewindDone(error.toZcashError()))
                                    .eraseToAnyPublisher()
                            }
                            .receive(on: mainQueue)
                    }
                    .cancellable(id: state.CancelResyncStateId, cancelInFlight: true),
                    .send(.batteryStateChanged)
                )
                
            case .rewindDone(let zcashError):
                if zcashError == nil {
                    //return .send(.home(.smartBanner(.evaluatePriority45)))
                }
                return .none

                // MARK: - Flexa

            case .flexaOpenRequest:
                flexaHandler.open()
                return .publisher {
                    flexaHandler.onTransactionRequest()
                        .map(Root.Action.flexaOnTransactionRequest)
                        .receive(on: mainQueue)
                }
                .cancellable(id: state.CancelFlexaId, cancelInFlight: true)
                
                // MARK: - Currency Conversion Setup
                
            case .currencyConversionSetup(.skipTapped), .currencyConversionSetup(.enableTapped):
                state.path = nil
                state.homeState.isRateEducationEnabled = false
                return .send(.home(.smartBanner(.closeAndCleanupBanner)))

                // MARK: - Home

            case .home(.settingsTapped):
                state.settingsState = .initial
                state.path = .settings
                return .none
                
            case .home(.receiveTapped):
                state.receiveState = .initial
                state.path = .receive
                return .none

            case .home(.sendTapped):
                state.sendCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .sendCoordFlow
                exchangeRate.refreshExchangeRateUSD()
                return .none

            case .home(.scanTapped):
                state.scanCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .scanCoordFlow
                return .none

            case .home(.flexaTapped), .settings(.payWithFlexaTapped):
                return .send(.flexaOpenRequest)
                
            case .home(.addKeystoneHWWalletTapped):
                state.addKeystoneHWWalletCoordFlowState = .initial
                state.path = .addKeystoneHWWalletCoordFlow
                return .none
                
            case .home(.swapWithNearTapped):
                state.swapAndPayCoordFlowState = .initial
                state.swapAndPayCoordFlowState.isSwapExperience = true
                state.swapAndPayCoordFlowState.swapAndPayState.isSwapExperienceEnabled = true
                state.path = .swapAndPayCoordFlow
                // whether to start on SwapToZEC or fromZEC
                return .send(.swapAndPayCoordFlow(.swapAndPay(.enableSwapToZecExperience)))

            case .home(.payWithNearTapped):
                state.offrampState = .initial(page: .amount, corridorContext: .payment)
                state.path = .offramp
                return .none

            case .home(.transactionList(.transactionTapped(let txId))):
                state.transactionsCoordFlowState = .initial
                state.transactionsCoordFlowState.transactionToOpen = txId
                if let index = state.transactions.index(id: txId) {
                    state.transactionsCoordFlowState.transactionDetailsState.transaction = state.transactions[index]
                }
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .transactionsCoordFlow
                return .none

            case .home(.seeAllTransactionsTapped):
                state.transactionsCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .transactionsCoordFlow
                return .none
                
            case .home(.currencyConversionSetupTapped):
                state.currencyConversionSetupState = .initial
                state.path = .currencyConversionSetup
                return .none

            case .home(.torSetupTapped(let settingsView)):
                state.torSetupState = .initial
                state.torSetupState.isSettingsView = settingsView
                state.path = .torSetup
                return .none

            case .home(.smartBanner(.walletBackupTapped)):
                state.walletBackupCoordFlowState = .initial
                state.path = .walletBackup
                return .none
                
            case .home(.smartBanner(.serverSwitchRequested)):
                state.serverSetupState = .initial
                state.path = .serverSwitch
                return .none

                // MARK: - Chats tab

            case .zappTabs(.chatProfileTapped):
                state.chatProfileState = .initial
                state.path = .chatProfile
                return .none

                // Only a group has anything behind its title.
            case .chatRoom(.titleTapped):
                guard let conversation = state.chatRoomState.conversation,
                      conversation.type == .group else {
                    return .none
                }
                state.groupInfoState = .initial
                state.groupInfoState.conversation = conversation
                state.path = .groupInfo
                return .none

                // Send ZEC from the composer's attachment sheet. The address is whatever the peer
                // shared in this chat, else their saved contact row — Android's
                // `onSendZecClick`. With neither, the room asks for the scanner instead and this
                // case never fires.
            case .chatRoom(.sendZecTapped):
                guard let address = state.chatRoomState.resolvedPeerWalletAddress else {
                    return .none
                }
                state.sendCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = true
                // No request id: this send settles nothing, it is just a payment to the peer.
                state.chatSendContext = .init(conversationId: state.chatRoomState.conversationId)
                state.path = .sendCoordFlow
                exchangeRate.refreshExchangeRateUSD()
                return .send(.sendCoordFlow(.sendForm(.addressUpdated(address.redacted))))

                // A shared wallet-address bubble tapped into a send — Android's `onSendToAddress`,
                // which is `onPayRequest` minus the amount prefill.
            case .chatRoom(.sendToAddressTapped(let address)):
                guard !address.isEmpty else { return .none }

                state.sendCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = true
                state.chatSendContext = .init(conversationId: state.chatRoomState.conversationId)
                state.path = .sendCoordFlow
                exchangeRate.refreshExchangeRateUSD()
                return .send(.sendCoordFlow(.sendForm(.addressUpdated(address.redacted))))

                // Paying a payment request — Android's `onPayRequest`. The address comes off the
                // request itself when it carries one, else it falls back to the same peer-address
                // resolution Send ZEC uses. The amount and memo prefill the form, and the request
                // id rides along so the receipt posted afterwards can settle this exact request.
            case .chatRoom(.payRequestTapped(let message)):
                let request = ChatPaymentRequest.parse(message.content)

                guard
                    let address = request.requesterAddress ?? state.chatRoomState.resolvedPeerWalletAddress,
                    !address.isEmpty
                else {
                    return .none
                }

                state.sendCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = true
                state.chatSendContext = .init(
                    conversationId: state.chatRoomState.conversationId,
                    requestId: request.id
                )
                state.path = .sendCoordFlow

                if let memo = request.memo {
                    state.sendCoordFlowState.sendFormState.memoState.text = memo
                }

                exchangeRate.refreshExchangeRateUSD()

                // An out-of-range amount is dropped rather than prefilled, exactly as Android
                // does — the send form then opens with the address only.
                guard request.isAmountValid else {
                    return .send(.sendCoordFlow(.sendForm(.addressUpdated(address.redacted))))
                }

                return .merge(
                    .send(.sendCoordFlow(.sendForm(.addressUpdated(address.redacted)))),
                    .send(.sendCoordFlow(.sendForm(.zecAmountUpdated(ChatAmountFormat.zec(request.amount).redacted))))
                )

                // The tx id comes from a peer, so it may name a transaction this wallet has never
                // seen. Android checks its own transaction list before navigating and toasts
                // otherwise; opening the detail blindly would leave it loading forever.
            case .chatRoom(.viewTransactionTapped(let txId)):
                guard state.transactions.index(id: txId) != nil else {
                    return .send(.chatRoom(.transactionUnavailable))
                }

                state.transactionsCoordFlowState = .initial
                state.transactionsCoordFlowState.transactionToOpen = txId
                if let index = state.transactions.index(id: txId) {
                    state.transactionsCoordFlowState.transactionDetailsState.transaction = state.transactions[index]
                }
                state.returnsToChatRoomAfterWalletFlow = true
                state.path = .transactionsCoordFlow
                return .none

                // Falls out of Send ZEC when no peer address is known. The scanner ends in the
                // same send form, so it returns to the room on the way out too — and it is still
                // a chat-initiated send, so it carries the same receipt context.
            case .chatRoom(.scanWalletAddressTapped):
                state.scanCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = true
                state.chatSendContext = .init(conversationId: state.chatRoomState.conversationId)
                state.path = .scanCoordFlow
                return .none

                // MARK: - Chat payment receipt

                // Android's `SubmitProposalUseCase.notifyChatPeer`. A send that was started from
                // a chat room and FULLY succeeded posts an `application/zec-transaction` receipt
                // back into that conversation; the peer renders it as a transaction bubble, and
                // when it quotes a `requestId` the matching payment request flips to Paid.
                //
                // The context is consumed on every resolution, not only on success: leaving it
                // set would let it attach to the next, unrelated send. Only `.success` posts —
                // a failure or a partial receipt would tell the requester money landed when it
                // did not, which is the one mistake worth being strict about.
            case let .sendCoordFlow(.resolveSendResult(result, confirmationState)),
                let .scanCoordFlow(.resolveSendResult(result, confirmationState)):
                guard let context = state.chatSendContext else { return .none }

                state.chatSendContext = nil

                guard result == .success else { return .none }

                // Multi-transaction proposals (TEX two-step, shield-then-spend) submit several
                // txs; naming one would link the receipt to the wrong transaction, so the id is
                // omitted and the bubble simply is not tappable — Android's `singleOrNull()`.
                let isSingleTransaction = confirmationState.proposal?.transactionCount() == 1
                let txId = isSingleTransaction ? confirmationState.txIdToExpand : nil

                guard let payload = ChatTransactionReceipt.json(
                    amount: confirmationState.amount.decimalValue.decimalValue,
                    requestId: context.requestId,
                    txId: txId?.isEmpty == false ? txId : nil
                ) else {
                    return .none
                }

                return .run { _ in
                    _ = try await zappMessaging.sendTransactionReceipt(context.conversationId, payload)
                } catch: { error, _ in
                    // Best effort, exactly like Android's `Twig.warn` — the money moved either
                    // way, and failing the send over a chat notification would be worse.
                    LoggerProxy.error("Failed to post chat transaction receipt: \(error)")
                }

                // Leaving drops you out of the group entirely, so go back to the list
                // rather than to a room that no longer exists.
            case .groupInfo(.didLeave):
                state.path = nil
                return .run { _ in try? await zappMessaging.refreshConversations() }

            case .zappTabs(.chatContactsTapped):
                state.chatContactsListState = .initial
                state.path = .chatContacts
                return .none

                // The feature owns no shared state; Root does. A mutation comes back
                // up here so every screen reading @Shared sees it at once.
            case .chatContactsList(.contactsChanged(let contacts)):
                return .send(.chatContactsLoaded(contacts))

                // Declining the messaging terms must not leave the user sitting in Chats behind a
                // dismissed gate, so the tab bounces back to wherever they came from.
            case .chatsList(.termsDeclined):
                state.zappTabsState.selectedTab = state.zappTabsState.previousTab
                return .none

            case .chatsList(.newConversationTapped):
                state.newChatState = .initial
                state.path = .newChat
                return .none

                // Creating a conversation lands the user straight in it, rather than
                // back on a list they then have to find it in.
            case .newChat(.created(let conversation)):
                state.chatRoomState = .initial
                state.chatRoomState.conversationId = conversation.id
                state.chatRoomState.conversation = conversation
                state.path = .chatRoom
                return .none

            case .chatsList(.conversationTapped(let conversationId)):
                state.chatRoomState = .initial
                state.chatRoomState.conversationId = conversationId
                // Carry the conversation across, or the room has no name to show
                // and falls back to "Chat".
                state.chatRoomState.conversation = state.chatsListState.conversations
                    .first { $0.id == conversationId }
                state.path = .chatRoom
                return .none

                // MARK: - You tab

            case .zappTabs(.allSettingsTapped):
                state.settingsState = .initial
                state.path = .settings
                return .none

            case .zappTabs(.appLockTapped):
                state.securitySettingsState = .initial
                state.path = .securitySettings
                return .none

                // Leaving the App lock screen (via its menu back button) returns to the You tab.
            case .securitySettings(.closeRequested):
                state.path = nil
                return .none

            case .zappTabs(.chooseServerTapped):
                state.serverSetupState = .initial
                state.path = .serverSwitch
                return .none

            case .zappTabs(.localCurrencyTapped):
                state.currencyConversionSetupState = .initial
                state.currencyConversionSetupState.isSettingsView = true
                state.path = .currencyConversionSetup
                return .none

            case .zappTabs(.p2pPaymentMethodTapped):
                state.offrampState = .initial(page: .corridors)
                state.path = .offramp
                return .none

            case .zappTabs(.p2pTransactionsTapped):
                state.offrampState = .initial(page: .history)
                state.path = .offramp
                return .none

            case .zappTabs(.readReceiptsTapped):
                state.path = .chatReadReceipts
                return .none

            case .zappTabs(.onlineStatusTapped):
                state.path = .chatOnlineStatus
                return .none

            case .zappTabs(.torTapped):
                state.torSetupState = .initial
                state.torSetupState.isSettingsView = true
                state.path = .torSetup
                return .none

                // MARK: - Keystone

            case .sendCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.rejectTapped)))),
                    .signWithKeystoneCoordFlow(.sendConfirmation(.rejectTapped)),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.rejectTapped)))):
                state.path = nil
                return .none

            case .signWithKeystoneRequested:
                state.signWithKeystoneCoordFlowBinding = true
                return .send(.signWithKeystoneCoordFlow(.sendConfirmation(.resolvePCZT)))
                
                // MARK: - Request Zec

            case .requestZecCoordFlow(.path(.element(id: _, action: .requestZecSummary(.cancelRequestTapped)))):
                state.path = nil
                return .none

                // MARK: - Reset Zashi

            case .settings(.path(.element(id: _, action: .disconnectHWWallet(.disconnectFinished)))):
                state.path = nil
                state.$selectedWalletAccount.withLock { $0 = nil }
                return .merge(
                    .send(.offramp(.cancelAll)),
                    .run { send in
                        let walletAccounts = try await sdkSynchronizer.walletAccounts()
                        await send(.initialization(.loadedWalletAccounts(walletAccounts)))
                        await send(.fetchTransactionsForTheSelectedAccount)
                        await send(.home(.walletBalances(.updateBalances)))
                        /// The TCA spins an async Task in `fetchTransactionsForTheSelectedAccount` and it's needed to run
                        /// before next code here therefore Task is asleep for 0.01s. The purpose is also to not block the main thread
                        /// so await of mainQueue is not used.
                        try? await Task.sleep(nanoseconds: 10_000_000)
                        await send(.resolveMetadataEncryptionKeys)
                        await send(.loadUserMetadata)
                    }
                )

            case .settings(.path(.element(id: _, action: .resetZashi(.deleteTapped(let areMetadataPreserved))))):
                return .send(.initialization(.resetZashiRequest(areMetadataPreserved)))

                // MARK: - Restore Wallet Coord Flow from Onboarding

            case .onboarding(.path(.element(id: _, action: .restoreInfo(.gotItTapped)))):
                var leavesScreenOpen = false
                for element in state.onboardingState.path {
                    if case .restoreInfo(let restoreInfoState) = element {
                        leavesScreenOpen = restoreInfoState.isAcknowledged
                    }
                }
                userDefaults.setValue(leavesScreenOpen, Constants.udLeavesScreenOpen)
                state.isRestoringWallet = true
                userDefaults.setValue(true, Constants.udIsRestoringWallet)
                state.$walletStatus.withLock { $0 = .restoring }
                return .concatenate(
                    .send(.initialization(.checkBackupPhraseValidation)),
                    .send(.batteryStateChanged)
                )

                // MARK: - Scan Coord Flow
                
                // A scan started from a chat room unwinds back onto that room, the same way the
                // send flow it feeds does. Every other entry point still unwinds to the tabs.
            case .scanCoordFlow(.scan(.cancelTapped)), .scanCoordFlow(.path(.element(id: _, action: .sendForm(.dismissRequired)))):
                state.path = state.returnsToChatRoomAfterWalletFlow ? .chatRoom : nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .none

            case .scanCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.path = nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .none

            case .scanCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = state.returnsToChatRoomAfterWalletFlow ? .chatRoom : nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .send(.fetchTransactionsForTheSelectedAccount)

                // MARK: - Self

            case .sendAgainRequested(let transactionState):
                state.sendCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .sendCoordFlow
                state.sendCoordFlowState.sendFormState.memoState.text = state.transactionMemos[transactionState.id]?.first ?? ""
                return .merge(
                    .send(.sendCoordFlow(.sendForm(.zecAmountUpdated(transactionState.amountWithoutFee.decimalString().redacted)))),
                    .send(.sendCoordFlow(.sendForm(.addressUpdated(transactionState.address.redacted))))
                )
                
            case .deeplinkWarning(.rescanInZashi):
                state = .initial
                state.splashAppeared = true
                return .merge(
                    .send(.destination(.updateDestination(.home))),
                    .send(.home(.scanTapped))
                )

                // MARK: - Send Coord Flow

                // A send started from a chat returns to that chat, the way Android's send screen
                // pops back onto the room it was pushed from. Every other entry point still
                // unwinds to the tabs.
            case .sendCoordFlow(.sendForm(.dismissRequired)):
                state.path = state.returnsToChatRoomAfterWalletFlow ? .chatRoom : nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .none

            case .sendCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .sendCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .sendCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = state.returnsToChatRoomAfterWalletFlow ? .chatRoom : nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .sendCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.path = nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .none

                // MARK: - Sign with Keystone Coord Flow

            case .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.signWithKeystoneCoordFlowBinding = false
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .signWithKeystoneCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.signWithKeystoneCoordFlowBinding = false
                return .none

                // MARK: - Tor Setup
                
            case .torSetup(.disableTapped), .torSetup(.enableTapped):
                state.path = nil
                return .send(.home(.smartBanner(.closeAndCleanupBanner)))

                // MARK: - Swap and Pay Coord Flow

            case .swapAndPayCoordFlow(.path(.element(id: _, action: .swapToZecSummary(.sentTheFundsButtonTapped)))):
                state.path = nil
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .swapAndPayCoordFlow(.customBackRequired):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.swapAndPay(.customBackRequired)):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.path(.element(id: _, action: .swapAndPayOptInForced(.customBackRequired)))):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.swapAndPay(.cancelPaymentTapped)):
                state.path = nil
                return .none
                
            case .swapAndPayCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = nil
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .swapAndPayCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.path = nil
                return .none

                // MARK: - Transactions Coord Flow
                
                // A detail opened from a chat bubble unwinds back onto that room, the way the send
                // and scan flows started from a room already do.
            case .transactionsCoordFlow(.transactionDetails(.closeDetailTapped)),
                .transactionsCoordFlow(.transactionsManager(.dismissRequired)):
                state.path = state.returnsToChatRoomAfterWalletFlow ? .chatRoom : nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .none

            case .transactionsCoordFlow(.transactionDetails(.sendAgainTapped)):
                state.path = nil
                let transactionState = state.transactionsCoordFlowState.transactionDetailsState.transaction
                return .run { send in
                    try? await mainQueue.sleep(for: .seconds(0.8))
                    await send(.sendAgainRequested(transactionState))
                }
                
            case .transactionsCoordFlow(.path(.element(id: _, action: .transactionDetails(.sendAgainTapped)))):
                for element in state.transactionsCoordFlowState.path {
                    if case .transactionDetails(let transactionDetailsState) = element {
                        state.path = nil
                        return .run { send in
                            try? await mainQueue.sleep(for: .seconds(0.8))
                            await send(.sendAgainRequested(transactionDetailsState.transaction))
                        }
                    }
                }
                return .none

                // MARK: - Wallet Backup Coord Flow

            case .walletBackupCoordFlow(.path(.element(id: _, action: .phrase(.remindMeLaterTapped)))):
                state.path = nil
                return .send(.home(.smartBanner(.remindMeLaterTapped(.priority6))))

            case .walletBackupCoordFlow(.path(.element(id: _, action: .phrase(.seedSavedTapped)))):
                state.path = nil
                do {
                    try walletStorage.markUserPassedPhraseBackupTest(true)
                } catch {
                    state.alert = AlertState.cantStoreThatUserPassedPhraseBackupTest(error.toZcashError())
                }
                return .merge(
                    .send(.home(.smartBanner(.closeAndCleanupBanner))),
                    .send(.home(.smartBanner(.closeSheetTapped)))
                )

            default: return .none
            }
        }
    }
}
