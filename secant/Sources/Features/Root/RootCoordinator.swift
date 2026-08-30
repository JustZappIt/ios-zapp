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
                .onramp(.delegate(.close)),
                .offramp(.delegate(.close)),
                .receive(.backToHomeTapped),
                .walletBackupCoordFlow(.backToHomeTapped),
                .torSetup(.backToHomeTapped),
                .portfolioChartSetup(.backToHomeTapped),
                .currencyConversionSetup(.backToHomeTapped),
                .backToHomeFromChatPrivacyTapped,
                .backToHomeFromServerSwitchTapped:
                state.path = nil
                return .none

                // MARK: - Ironwood Announcement

            case .ironwoodAnnouncement(.continueTapped):
                // The child already wrote the acknowledgement. Routing through
                // Destination rather than assigning directly delivers any
                // stale-wallet-healed alert deferred while this screen was up.
                return .send(.destination(.updateDestination(.home)))

            case .settings(.path(.element(id: _, action: .advancedSettings(.debugResetIronwoodAnnouncementTapped)))):
                // The debug row clears persistent acknowledgement; clear the
                // session latch too so the gate can be exercised immediately.
                state.ironwoodAnnouncementResolved = false
                return .none
                
                // MARK: - Accounts

            case .home(.walletAccountTapped(let walletAccount)):
                guard state.selectedWalletAccount != walletAccount else {
                    return .none
                }
                state.$selectedWalletAccount.withLock { $0 = walletAccount }
                let switchedEffect = accountSwitchedEffect(state: &state)
                return .merge(
                    .send(.onramp(.cancelAll)),
                    .send(.offramp(.cancelAll)),
                    switchedEffect,
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
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

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .keystoneDeviceReady(.accountImportSucceeded)))):
                // `AddHWWalletStore`'s `.loadedWalletAccounts` handler, fired immediately before
                // this action within the same `.run` effect as `.accountImported`, writes
                // `selectedWalletAccount` directly with no Root-visible switch action of its own.
                // This is the earliest point Root can react, so transaction and balance refreshes
                // happen now rather than waiting for `.keystoneConnected(.closeTapped)`. That close
                // handler still refetches; the duplication is harmless because fetched payloads now
                // carry account provenance. Navigation remains owned by the Keystone coordinator,
                // so this arm leaves `state.path` untouched.
                //
                // Metadata must reload here too: transaction decoration reads the single in-memory
                // `userMetadataProvider` state, which may still belong to the previous account. A
                // newly imported account also has no metadata encryption keys yet, so resolving keys
                // provisions every account just repopulated by `.loadedWalletAccounts` before
                // `.loadUserMetadata` selects the imported account's metadata.
                let switchedEffect = accountSwitchedEffect(state: &state)
                return .merge(
                    switchedEffect,
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    )
                )

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .accountHWWalletSelection(.accountImportSucceeded)))):
                state.path = nil
                let switchedEffect = accountSwitchedEffect(state: &state)
                return .merge(
                    switchedEffect,
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    )
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
                let switchedEffect = accountSwitchedEffect(state: &state)
                return .merge(
                    switchedEffect,
                    .send(.loadContacts),
                    .send(.loadChatContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    )
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

                // Android's `HomeVM.onSendButtonClick` → `UnifiedSendArgs()`: the unified form with
                // ZEC selected.
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
                
                // The Pay tab's Swap action lands on the *same* unified form as Send, already in
                // swap mode — Android's unified screen with a non-ZEC asset picked. `SwapAndPay`
                // pre-selects the last-used asset (else BTC) once the asset list loads.
            case .home(.swapWithNearTapped):
                state.sendCoordFlowState = .initial
                state.sendCoordFlowState.mode = .swap
                state.sendCoordFlowState.swapState.isSwapExperienceEnabled = true
                state.sendCoordFlowState.swapState.isSwapToZecExperienceEnabled = false
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .sendCoordFlow
                exchangeRate.refreshExchangeRateUSD()
                return .none

                // The primary action resolves the stored rail rather than assuming one. A Peer
                // selection can outlive the build that offered it — a flavour switch leaves it
                // behind — so availability is confirmed before the flow opens, not after.
            case .home(.payWithNearTapped):
                let isSoftwareWallet = state.selectedWalletAccount?.vendor == .zcash
                return .run { send in
                    guard
                        isSoftwareWallet,
                        case let .peerCashOut(destinationCode) = userStoredPreferences.p2pRail() ?? .default,
                        try await peerCashOut.capabilities().isAvailable
                    else {
                        return await send(.openScanAndPay)
                    }
                    await send(.openPeerCashOut(destinationCode: destinationCode))
                } catch: { _, send in
                    await send(.openScanAndPay)
                }

            case .openScanAndPay:
                state.offrampState = .initial(page: .amount, corridorContext: .payment)
                state.path = .offramp
                return .none

            case let .openPeerCashOut(destinationCode):
                state.peerCashOutState = PeerCashOut.State(destinationCode: destinationCode)
                state.path = .peerCashOut
                return .none

                // Topping up is the off-ramp's bridge screen with its own progress and its own
                // authentication; a cash-out never starts one behind the user's back.
            case .peerCashOut(.delegate(.topUp)):
                state.offrampState = .initial(page: .amount, corridorContext: .settings)
                state.path = .offramp
                return .send(.offramp(.addFundsTapped))

            case .peerCashOut(.delegate(.close)), .p2pPaymentMethod(.delegate(.close)):
                state.path = nil
                return .none

            case .home(.buyTapped):
                state.onrampState = .initial(currencyCode: state.offrampState.selectedCurrencyCode)
                state.path = .onramp
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

            case .home(.migrationTapped):
                return openMigrationCoordFlow(state: &state)

            case .migrationCoordFlow(.switchServerRequested):
                // N6: the Tor sheet's custom-server escape. Tear the flow down (which discards the
                // still-PROVISIONAL network snapshot — nothing was committed) and open Server Setup.
                // A re-entry afterwards re-forms and re-rolls the endpoint.
                // Reuse the smart banner's own Server Setup entry (the one existing precedent),
                // rather than a second route to the same screen.
                state.serverSetupState = .initial
                state.path = .serverSwitch
                // Audit 2026-08-03 (#15+#19): this teardown is a flow CLOSE like `flowFinished` —
                // it must disarm the flow-presented guard and re-run the re-arms the other close
                // path always had (the banner poke, and the tick respawn a mid-session commit
                // relies on), or a tick loop that self-cancelled earlier stays dead until the
                // next app-open. (The Send-now fence clear that lived here was REMOVED 2026-08-07
                // with the Send-now lanes.)
                migrationManager.setMigrationFlowPresented(state.selectedWalletAccount?.id, false)
                return .merge(
                    .run { [migrationManager, accountUUID = state.selectedWalletAccount?.id] _ in
                        await migrationManager.clearAbandonedNetworkSnapshot(accountUUID)
                    },
                    .send(.home(.smartBanner(.migrationReevaluationRequested))),
                    migrationTickLoopEffect(state: state)
                )

            // G1 (field 2026-08-05): THE IN-FLOW COMMIT CURE. `flowFinished` below re-spawns the
            // tick loop for a run committed mid-session — but only when the user LEAVES the flow,
            // and the session that commits then sits watching the progress screen never does: its
            // R0 open-lane credit is long spent (the log's "afterSync SKIPPED — already driven"),
            // no sync edge is coming on an up-to-date wallet, and the loop was never spawned
            // because the app-open's spawn ran before the run existed. The banner honestly said
            // "Keep Zodl open" while nothing in the session could ever discharge the first
            // preparation. So: spawn the loop the moment the run is BORN, from both commit
            // delegates (the scheduled plan's and the review screen's). Idempotent —
            // `cancelInFlight: true` makes a duplicate spawn a restart, and every guard
            // (off switch, activation, committed candidate) lives inside the effect itself.
            // And drive the newborn run's first step RIGHT NOW (Lukas, 2026-08-05: "I was hoping
            // to trigger first nextStep with the start migration button") — the same at-tip
            // `.afterSync` drive `flowFinished` runs, which works here because the commit itself
            // refunded the session's open-lane credits (`recordCommittedSchedule` — a newborn run
            // is not the state the pre-commit pass drove). Mid-sync, the guard defers to the
            // coming edge, whose own drive now also holds a fresh credit. The tick loop stays the
            // belt for everything after.
            // Field 2026-08-06: the scheduled-plan lane now front-runs this same drive UNDER THE
            // CONFIRM LOADER, awaited, before `.transferPlan`'s `.delegate(.confirmed)` ever fires
            // (`MigrationTransferPlan`'s `.scheduleCommitted` — see its doc). So for that lane this
            // call is now an idempotent backstop, not the first driver — it still fires here every
            // time, on the same phase token and the same at-tip guard, and the tick-loop spawn
            // above still matters regardless of which lane fired it. NOT a backstop for a back-tap
            // during the drive wait, though: that pops the path element before `.delegate(.confirmed)`
            // can ever fire, so this case never matches on that path (TCA's `forEach` cancels the
            // in-flight `.scheduleCommitted` effect on the pop, so its trailing
            // `send(.scheduleSigned)` is a no-op) — that path is recovered by `flowFinished` below
            // (fires when the coordinator closes) and, failing that, the next app-open's re-arm in
            // `RootInitialization`, not by this case. The drive itself keeps running regardless —
            // it's unstructured specifically so the pop's cancellation can't reach it (see
            // `.scheduleCommitted`'s own doc). This case remains the ONLY drive for the
            // `.reviewTransfer` lane below, which gained no loader-side drive of its own.
            case .migrationCoordFlow(.path(.element(id: _, action: .transferPlan(.delegate(.confirmed))))),
                .migrationCoordFlow(.path(.element(id: _, action: .reviewTransfer(.delegate(.confirmed))))):
                return .merge(
                    migrationTickLoopEffect(state: state),
                    .run { [migrationManager, sdkSynchronizer] _ in
                        guard case .upToDate = sdkSynchronizer.latestState().syncStatus else { return }
                        await migrationManager.advance(.afterSync)
                    }
                )

            case .migrationCoordFlow(.flowFinished):
                state.path = nil
                // Audit 2026-08-03 (#15): the flow-presented guard's disarm — see the coordinator
                // `.onAppear` arm for the plan-cache race this pair closes.
                migrationManager.setMigrationFlowPresented(state.selectedWalletAccount?.id, false)
                // (The Send-now fence clear that lived here was REMOVED 2026-08-07 with the
                // Send-now lanes.)
                // A finished run has usually changed what there is to migrate — after the manual
                // lane, to nothing at all. Poke the banner to re-derive rather than waiting for a
                // sync transition to do it: on an already-`.upToDate` wallet no transition is
                // coming, which is exactly how a completed manual migration was left advertising
                // itself on the Home screen (field-caught 2026-07-29). Harmless when nothing
                // changed — the re-read returns the same variant and re-renders in place.
                //
                // MOB-1466: the flow that just closed may have COMMITTED a scheduled run mid-session,
                // and the tick loop only spawns at app-open — re-spawn it here too (idempotent,
                // self-guarding: the off switch, activation, and scheduled-candidate checks all live
                // inside the effect itself).
                //
                // And drive the DRIVER once at `.afterSync` when the wallet is already at the tip
                // (field-caught 2026-08-02, the confirm-after-edge wedge): a run committed after
                // this app-open's one `.upToDate` edge has missed the only phase that may prove
                // (`.prove` defers as `.wrongPhase` at `.beforeSync` and `.tick` alike), so its
                // first preparation sat unproven until the next app-open — "no transition is
                // coming" applies to the driver exactly as it does to the banner above. Guarded on
                // the LIVE status at execution time: mid-sync, the coming edge owns this call
                // (`didJustReachUpToDate` in `synchronizerStateChanged`), and driving early would
                // sweep against a stale tip. The driver is single-flight and self-guarding, so a
                // flow that committed nothing degrades to one cheap `noRun` read.
                return .merge(
                    .send(.home(.smartBanner(.migrationReevaluationRequested))),
                    migrationTickLoopEffect(state: state),
                    .run { [migrationManager, sdkSynchronizer] _ in
                        guard case .upToDate = sdkSynchronizer.latestState().syncStatus else { return }
                        await migrationManager.advance(.afterSync)
                    },
                    // Audit 2026-08-03 (#6): a flow that closed WITHOUT committing leaves its
                    // Tor-sheet snapshot provisional — and nothing ever cleared it, pinning
                    // auto-server selection and arming ServerSetup's privacy warning for a run
                    // that does not exist. The cleaner no-ops when the flow committed (the
                    // confirm converted the snapshot) and when there is nothing to clear.
                    .run { [migrationManager, accountUUID = state.selectedWalletAccount?.id] _ in
                        migrationManager.clearProvisionalNetworkSnapshot(accountUUID)
                    }
                )

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

            case .chatProfile(.walletAddressTapped):
                state.chatWalletAddressState = .initial
                state.path = .chatWalletAddress
                return .none

                // Back to the profile, not to the tabs. `path` holds one destination at a time,
                // so a nested screen has to name the one it came from.
            case .chatWalletAddress(.backTapped):
                state.path = .chatProfile
                return .none

                // Android's `DeleteChatIdentityUseCase` shuts the messaging SDK down and then
                // deletes the wallet data and preferences behind it. On iOS that whole sequence
                // already exists as the reset the Settings path runs — including
                // `zappMessaging.wipe()` — so Delete identity reuses it rather than
                // half-deleting an identity the wallet seed would immediately re-derive.
            case .chatProfile(.deleteIdentityConfirmed):
                return .send(.initialization(.resetZashiRequest(false)))

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

                // Since the send form and the swap form became one screen, a send started from a
                // chat room can be switched to swap mode and resolve through this very case. That
                // ZEC went to the swap provider's deposit address, not to the peer: a receipt would
                // tell them they were paid when they were not, and would flip a quoted payment
                // request to Paid while it is still owed. Only a plain ZEC send notifies the peer.
                // The context is consumed above either way, so it cannot attach to a later send.
                guard confirmationState.type == .regular else { return .none }

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
            case .chatContactsList(.contactsChanged(let contacts)),
                .chatRoom(.contactsChanged(let contacts)):
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

                // MARK: - Zapp Support

                // The pinned support row opens the TICKET LIST, never a chat room: a user may have
                // several open tickets and the row aggregates them (Android's `onSupportClick`).
            case .chatsList(.supportRowTapped):
                state.supportTicketListState = .initial
                state.path = .supportTicketList
                return .none

            case .supportTicketList(.backTapped):
                state.path = nil
                return .none

            case .supportTicketList(.newTicketTapped):
                state.supportChatState = .init()
                state.path = .supportChat
                return .none

            case .supportTicketList(.ticketTapped(let conversationId)):
                state.supportChatState = .init(conversationId: conversationId)
                state.path = .supportChat
                return .none

                // Both leaving and closing a ticket land back on the ticket list, which is where
                // Android's `navigationRouter.back()` returns from the support chat.
            case .supportChat(.backTapped), .supportChat(.leaveFinished):
                state.path = .supportTicketList
                return .none

            case .chatsList(.conversationTapped(let conversationId)):
                state.chatRoomState = .initial
                state.chatRoomState.conversationId = conversationId
                state.chatRoomState.unreadMessageCountAtEntry =
                    state.chatsListState.messagingState.unreadCount(for: conversationId)
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
                state.p2pPaymentMethodState = .initial
                state.path = .p2pPaymentMethod
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

            case .zappTabs(.portfolioChartTapped):
                state.portfolioChartSetupState = .initial
                state.path = .portfolioChartSetup
                return .none

            case .settings(.path(.element(id: _, action: .migrationRestart(.delegate(.restarted))))):
                // MOB-1466 (Lukas, 2026-08-07): "once I finish restart migration, we need to reset
                // smart banner.. because it renders me 2 of 11 transactions done.. aka previous
                // state."
                //
                // The restart cancels the run in the ENGINE and reconciles, but the banner holds
                // its own answer: the last variant, the dwell queue behind it, any held answer
                // waiting on a verdict, and the `.idle` termination latch that is deliberately
                // sticky for the rest of the session. None of that is invalidated by an engine
                // state change on its own — the banner would keep counting a run that no longer
                // exists until something re-asked.
                //
                // So: kill the cached answer and re-run the priority ladder from the top. The
                // ladder re-asks the manager, which now sees no run and Orchard funds still to
                // move, and hands back `.required` — the user is offered the migration again,
                // which is the whole point of restarting.
                //
                // Sent from `Root` rather than from Settings because the banner lives under Home;
                // Settings has no path to it.
                return .send(.home(.smartBanner(.migrationRunReset)))

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
                    .send(.onramp(.cancelAll)),
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

                // Android's `OnAddressScannedUseCase` HOMEPAGE branch: a scanned address *replaces*
                // the scanner with the unified send form rather than opening a send form of the
                // scanner's own. The chat context (if the scanner was opened from a room) rides
                // along untouched so the receipt still posts and the flow still returns to the room.
            case .scanCoordFlow(.sendRequested(let address)):
                let returnsToChatRoom = state.returnsToChatRoomAfterWalletFlow
                let chatSendContext = state.chatSendContext
                state.sendCoordFlowState = .initial
                state.returnsToChatRoomAfterWalletFlow = returnsToChatRoom
                state.chatSendContext = chatSendContext
                state.path = .sendCoordFlow
                exchangeRate.refreshExchangeRateUSD()
                return .send(.sendCoordFlow(.sendForm(.addressUpdated(address))))

                // MOB-1581: refresh immediately for every terminal send outcome that stored a
                // transaction. An idle wallet may emit no sync event until the next block, and
                // `sendFailed(_, false)` deliberately remains silent because nothing was stored.
            case .scanCoordFlow(.path(.element(id: _, action: .sendConfirmation(.sendDone)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendConfirmation(.sendPartial)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendConfirmation(.sendFailed(_, true))))),
                    .scanCoordFlow(.path(.element(id: _, action: .requestZecConfirmation(.sendDone)))),
                    .scanCoordFlow(.path(.element(id: _, action: .requestZecConfirmation(.sendPartial)))),
                    .scanCoordFlow(.path(.element(id: _, action: .requestZecConfirmation(.sendFailed(_, true))))),
                    .scanCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendDone)))),
                    .scanCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendPartial)))),
                    .scanCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendFailed(_, true))))):
                return .send(.fetchTransactionsForTheSelectedAccount)

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
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .scanCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = state.returnsToChatRoomAfterWalletFlow ? .chatRoom : nil
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                return .send(.fetchTransactionsForTheSelectedAccount)

                // MARK: - Self

                // Android's `SendTransactionAgainUseCase`:
                // `UnifiedSendArgs(isScanZip321Enabled = false)` + a prefill of the original
                // address/amount/memo.
            case .sendAgainRequested(let transactionState):
                state.sendCoordFlowState = .initial
                state.sendCoordFlowState.isScanZip321Enabled = false
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

                // MOB-1581: refresh immediately for every terminal send outcome that stored a
                // transaction. `sendFailed(_, false)` stored nothing and must stay silent.
            case .sendCoordFlow(.path(.element(id: _, action: .sendConfirmation(.sendDone)))),
                    .sendCoordFlow(.path(.element(id: _, action: .sendConfirmation(.sendPartial)))),
                    .sendCoordFlow(.path(.element(id: _, action: .sendConfirmation(.sendFailed(_, true))))),
                    .sendCoordFlow(.path(.element(id: _, action: .requestZecConfirmation(.sendDone)))),
                    .sendCoordFlow(.path(.element(id: _, action: .requestZecConfirmation(.sendPartial)))),
                    .sendCoordFlow(.path(.element(id: _, action: .requestZecConfirmation(.sendFailed(_, true))))),
                    .sendCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendDone)))),
                    .sendCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendPartial)))),
                    .sendCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendFailed(_, true))))):
                return .send(.fetchTransactionsForTheSelectedAccount)

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
                return .send(.fetchTransactionsForTheSelectedAccount)

                // Android's `PrimaryButtonState.TopUp` → `TopUpArgs`. On iOS the bridge-funds
                // corridor lives in Offramp; `addFundsTapped` is the action that opens its Top-Up
                // page and loads the account behind it.
            case .sendCoordFlow(.topUpRequested):
                state.offrampState = .initial(page: .amount, corridorContext: .settings)
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .offramp
                return .send(.offramp(.addFundsTapped))

                // Swap-to-ZEC (deposit an external asset, receive ZEC) is not part of Android's
                // unified screen. It keeps its own flow, entered from the unified form's deposit
                // affordance so the corridor is not orphaned by the merge — this is the routing the
                // Pay tab's Swap action used before the two forms converged.
            case .sendCoordFlow(.swapToZecRequested):
                state.swapAndPayCoordFlowState = .initial
                state.swapAndPayCoordFlowState.isSwapExperience = true
                state.swapAndPayCoordFlowState.swapAndPayState.isSwapExperienceEnabled = true
                state.returnsToChatRoomAfterWalletFlow = false
                state.chatSendContext = nil
                state.path = .swapAndPayCoordFlow
                // whether to start on SwapToZEC or fromZEC
                return .send(.swapAndPayCoordFlow(.swapAndPay(.enableSwapToZecExperience)))

                // MARK: - Sign with Keystone Coord Flow

            case .signWithKeystoneCoordFlow(.sendConfirmation(.sendDone)),
                    .signWithKeystoneCoordFlow(.sendConfirmation(.sendPartial)),
                    .signWithKeystoneCoordFlow(.sendConfirmation(.sendFailed(_, true))):
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.signWithKeystoneCoordFlowBinding = false
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .signWithKeystoneCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.signWithKeystoneCoordFlowBinding = false
                return .send(.fetchTransactionsForTheSelectedAccount)

                // MARK: - Tor Setup
                
            case .torSetup(.disableTapped), .torSetup(.enableTapped):
                state.path = nil
                return .send(.home(.smartBanner(.closeAndCleanupBanner)))

                // MARK: - Swap and Pay Coord Flow

            case .swapAndPayCoordFlow(.sendDone),
                    .swapAndPayCoordFlow(.sendPartial),
                    .swapAndPayCoordFlow(.sendFailed(_, true)),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendDone)))),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendPartial)))),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.sendFailed(_, true))))):
                return .send(.fetchTransactionsForTheSelectedAccount)

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
                return .send(.fetchTransactionsForTheSelectedAccount)

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

    /// Applies the account-scoped reactions shared by a manual switch and every Keystone
    /// auto-selection signal. The transaction fetch cancellation must finish before the refetch is
    /// dispatched, or the switch could cancel its own work for the newly selected account.
    private func accountSwitchedEffect(state: inout Root.State) -> Effect<Root.Action> {
        state.autoUpdateSwapCandidates.removeAll()
        state.homeState.transactionListState.isInvalidated = true
        state.transactionsCoordFlowState.transactionsManagerState.isInvalidated = true
        return .merge(
            // Cancels and joins the Base rails, including any Peer cash-out still driving the
            // previous wallet's smart account. The rails rebuild lazily on the next P2P screen.
            .run { _ in await offramp.invalidateSession() },
            .send(.home(.smartBanner(.walletAccountChanged))),
            .send(.home(.walletBalances(.updateBalances))),
            .concatenate(
                .cancel(id: state.CancelTransactionsFetchId),
                .send(.fetchTransactionsForTheSelectedAccount)
            )
        )
    }
}
