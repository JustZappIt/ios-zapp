//
//  UnifiedSendEntryPointTests.swift
//  zodlTests
//
//  Phase 12 — every send entry point has to land on the ONE unified form, with the prefill Android
//  carries in `UnifiedSendArgs` (`recipientAddress`, `isScanZip321Enabled`). Android's entry points:
//  `HomeVM.onSendButtonClick`, the Pay tab's Swap action, `ChatRoomVM.onSendZecClick` /
//  `onSendToAddress` / `onPayRequest`, `OnAddressScannedUseCase` (HOMEPAGE) and
//  `SendTransactionAgainUseCase`.
//
//  These are Root-level: what matters is that `Root.path` becomes `.sendCoordFlow` — the unified
//  flow — with the right mode and prefill, and that no entry point reaches the swap form on its own.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Serialized: drives a Root store sharing process-global `@Shared` state.
@Suite(.serialized) @MainActor struct UnifiedSendEntryPointTests {
    private static let peerAddress = "tmP3uLtGx5GPddkq8a6ddmXhqJJ3vy6tpTE"
    /// A memo can only travel to a shielded recipient — `SendForm.addressUpdated` clears the memo
    /// for transparent/TEX addresses, so the memo prefill has to be asserted against a unified one.
    private static let shieldedAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    private func store(with state: Root.State) -> StoreOf<Root> {
        Store(initialState: state) {
            Root()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.mnemonic = .mock
            $0.offramp.accountSummary = {
                OfframpAccountModel(
                    address: "0xbridge",
                    balanceMicros: nil,
                    balanceDisplay: nil,
                    explorerURL: nil,
                    canBridgeToBase: true,
                    canRefundToZec: true
                )
            }
            $0.sdkSynchronizer = .noOp
            $0.walletStorage = .noOp
            $0.zcashSDKEnvironment = .testnet
        }
    }

    private func payTabStore() -> StoreOf<Root> {
        store(with: .initial)
    }

    private func chatRoomStore(peerSharedAddress: Bool = true) -> StoreOf<Root> {
        var state = Root.State.initial
        state.chatRoomState = ChatRoom.State(conversationId: "conversation")

        if peerSharedAddress {
            state.chatRoomState.messages = [
                ZMMessage(
                    id: "peer-1",
                    conversationId: "conversation",
                    senderId: "peer",
                    content: Self.peerAddress,
                    contentType: ChatContentType.walletAddress,
                    timestamp: Date(timeIntervalSince1970: 100),
                    isFromMe: false
                )
            ]
        }

        state.path = .chatRoom
        return store(with: state)
    }

    // MARK: - 1. Pay tab → Send

    @Test func payTabSendOpensTheUnifiedFormInZecMode() {
        let store = payTabStore()

        store.send(.home(.sendTapped))

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .zec)
        #expect(store.sendCoordFlowState.isScanZip321Enabled)
    }

    // MARK: - 2. Pay tab → Swap

    /// The Swap action no longer opens a second form: it opens the *same* unified form already in
    /// swap mode, with Android's EXACT_INPUT direction.
    @Test func payTabSwapOpensTheSameUnifiedFormInSwapMode() {
        let store = payTabStore()

        store.send(.home(.swapWithNearTapped))

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .swap)
        #expect(store.sendCoordFlowState.swapState.isSwapExperienceEnabled)
        #expect(!store.sendCoordFlowState.swapState.isSwapToZecExperienceEnabled)
    }

    /// Regression: the Swap action used to route to `SwapAndPayCoordFlow`. That flow must now only be
    /// reached from the unified form's deposit affordance.
    @Test func payTabSwapNoLongerReachesTheSwapAndPayFlowDirectly() {
        let store = payTabStore()

        store.send(.home(.swapWithNearTapped))

        #expect(store.path != .swapAndPayCoordFlow)
    }

    // MARK: - 3. Chat room entry points

    @Test func chatSendZecPrefillsThePeerAddressOnTheUnifiedForm() async {
        let store = chatRoomStore()

        store.send(.chatRoom(.sendZecTapped))
        await waitForRoot { store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress }

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .zec)
        #expect(store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress)
        #expect(store.returnsToChatRoomAfterWalletFlow)
        #expect(store.chatSendContext?.conversationId == "conversation")
    }

    @Test func chatSendToAddressPrefillsTheSharedAddress() async {
        let store = chatRoomStore(peerSharedAddress: false)

        store.send(.chatRoom(.sendToAddressTapped(Self.peerAddress)))
        await waitForRoot { store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress }

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .zec)
        #expect(store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress)
        #expect(store.returnsToChatRoomAfterWalletFlow)
    }

    /// Paying a payment request prefills address, amount and memo, and carries the request id so the
    /// receipt can settle it.
    @Test func chatPayRequestPrefillsAddressAmountAndMemo() async {
        let store = chatRoomStore(peerSharedAddress: false)
        let content = """
        {"id":"req-1","amount":0.25,"memo":"Taxi","requesterAddress":"\(Self.shieldedAddress)"}
        """

        store.send(
            .chatRoom(
                .payRequestTapped(
                    ZMMessage(
                        id: "req-msg",
                        conversationId: "conversation",
                        senderId: "peer",
                        content: content,
                        contentType: ChatContentType.paymentRequest,
                        timestamp: Date(timeIntervalSince1970: 200),
                        isFromMe: false
                    )
                )
            )
        )
        await waitForRoot { store.sendCoordFlowState.sendFormState.address.data == Self.shieldedAddress }

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .zec)
        #expect(store.sendCoordFlowState.sendFormState.address.data == Self.shieldedAddress)
        #expect(store.sendCoordFlowState.sendFormState.memoState.text == "Taxi")
        #expect(store.chatSendContext?.requestId == "req-1")
    }

    // MARK: - 4. Scanner (Android's OnAddressScannedUseCase, HOMEPAGE branch)

    /// A plain address scanned from the Pay tab's scanner now *replaces* the scanner with the unified
    /// form, prefilled — rather than pushing the scan flow's own second send form.
    @Test func aScannedAddressOpensTheUnifiedFormPrefilled() async {
        let store = payTabStore()

        store.send(.home(.scanTapped))
        #expect(store.path == .scanCoordFlow)

        store.send(.scanCoordFlow(.scan(.foundAddress(Self.peerAddress.redacted))))
        await waitForRoot { store.path == .sendCoordFlow }

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .zec)
        await waitForRoot { store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress }
        #expect(store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress)
    }

    /// The scanner opened from a chat room keeps its chat context across the handoff, so the receipt
    /// still posts and the flow still returns to the room.
    @Test func aScannedAddressFromAChatRoomKeepsTheChatContext() async {
        let store = chatRoomStore(peerSharedAddress: false)

        store.send(.chatRoom(.scanWalletAddressTapped))
        #expect(store.path == .scanCoordFlow)
        #expect(store.returnsToChatRoomAfterWalletFlow)

        store.send(.scanCoordFlow(.scan(.foundAddress(Self.peerAddress.redacted))))
        await waitForRoot { store.path == .sendCoordFlow }

        #expect(store.returnsToChatRoomAfterWalletFlow)
        #expect(store.chatSendContext?.conversationId == "conversation")
    }

    // MARK: - 5. Send again

    @Test func sendAgainOpensTheUnifiedFormWithZip321ScanningOff() async {
        let store = payTabStore()

        store.send(
            .sendAgainRequested(
                TransactionState(
                    zAddress: Self.peerAddress,
                    fee: Zatoshi(10_000),
                    id: "tx-id",
                    status: .sending,
                    zecAmount: Zatoshi(100_000)
                )
            )
        )
        await waitForRoot { store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress }

        #expect(store.path == .sendCoordFlow)
        #expect(store.sendCoordFlowState.mode == .zec)
        #expect(!store.sendCoordFlowState.isScanZip321Enabled)
        #expect(store.sendCoordFlowState.sendFormState.address.data == Self.peerAddress)
    }

    // MARK: - Corridors kept reachable

    /// Swap-to-ZEC is not part of the unified screen (Android's isn't either), so it keeps its own
    /// flow — reached from the unified form's deposit affordance.
    @Test func theDepositAffordanceStillReachesTheSwapToZecCorridor() async {
        let store = payTabStore()

        store.send(.home(.swapWithNearTapped))
        #expect(store.path == .sendCoordFlow)

        store.send(.sendCoordFlow(.swapToZecRequested))
        await waitForRoot { store.path == .swapAndPayCoordFlow }

        #expect(store.path == .swapAndPayCoordFlow)
        #expect(store.swapAndPayCoordFlowState.swapAndPayState.isSwapToZecExperienceEnabled)
    }

    /// Top Up hands off to the Offramp bridge-funds corridor (Android's `TopUpArgs`).
    @Test func topUpOpensTheOfframpBridgeCorridor() async {
        let store = payTabStore()

        store.send(.home(.sendTapped))
        store.send(.sendCoordFlow(.topUpRequested))
        await waitForRoot { store.path == .offramp }

        #expect(store.path == .offramp)
        await waitForRoot { store.offrampState.page == .topUp }
        #expect(store.offrampState.page == .topUp)
    }
}

@MainActor
private func waitForRoot(
    timeoutNanoseconds: UInt64 = 10_000_000_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(condition(), "Timed out waiting for the Root store", sourceLocation: sourceLocation)
}
