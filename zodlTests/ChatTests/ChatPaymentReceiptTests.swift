//
//  ChatPaymentReceiptTests.swift
//  zodlTests
//
//  Phase 6 — the payment round trip through Root: Pay on a request bubble opens the send flow
//  prefilled and remembers WHICH request it settles, and a fully successful send posts the
//  `application/zec-transaction` receipt that flips the requester's bubble to Paid.
//
//  The strictness here is deliberate. A receipt posted on anything less than a full success
//  tells the requester money landed when it did not, and a context left set would attach the
//  next unrelated send to the wrong conversation.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Serialized: drives a Root store sharing process-global `@Shared` state.
@Suite(.serialized) @MainActor struct ChatPaymentReceiptTests {
    /// The requester's own UNIFIED address — that is what Android puts in `requesterAddress`
    /// (`getZashiAccount().unified.address.address`), and a shielded recipient is also the case
    /// where a request's memo can actually travel.
    private static let peerAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    private func requestMessage(id: String, amount: String, memo: String? = nil) -> ZMMessage {
        let body = ChatPaymentRequest.json(
            id: id,
            amount: Decimal(string: amount) ?? 0,
            requesterAddress: Self.peerAddress,
            memo: memo
        ) ?? ""

        return ZMMessage(
            id: "msg-\(id)",
            conversationId: "conversation",
            senderId: "peer",
            content: body,
            contentType: ChatContentType.paymentRequest,
            timestamp: Date(timeIntervalSince1970: 100),
            isFromMe: false
        )
    }

    private func rootStore(
        sentReceipts: LockIsolated<[(conversationId: String, payload: String)]>? = nil
    ) -> StoreOf<Root> {
        var state = Root.State.initial
        state.chatRoomState = ChatRoom.State(conversationId: "conversation")
        state.path = .chatRoom

        return Store(initialState: state) {
            Root()
        } withDependencies: {
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.mnemonic = .mock
            $0.sdkSynchronizer = .noOp
            $0.walletStorage = .noOp
            $0.zcashSDKEnvironment = .testnet

            if let sentReceipts {
                $0.zappMessaging.sendTransactionReceipt = { conversationId, payload in
                    sentReceipts.withValue { $0.append((conversationId, payload)) }

                    return ZMMessage(
                        id: UUID().uuidString,
                        conversationId: conversationId,
                        senderId: "me",
                        content: payload,
                        contentType: ChatContentType.zecTransaction,
                        isFromMe: true
                    )
                }
            }
        }
    }

    private func confirmationState(amount: Zatoshi, txId: String?) -> SendConfirmation.State {
        var state = SendConfirmation.State(
            address: Self.peerAddress,
            amount: amount,
            feeRequired: Zatoshi(10_000),
            message: "",
            proposal: nil
        )
        state.txIdToExpand = txId

        return state
    }

    /// Root is driven through a live `Store`, so the receipt lands from an async effect. Polling on
    /// an observable signal keeps that deterministic — a fixed sleep passes alone and flakes under
    /// a full-suite run.
    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: Swift.Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if condition() { return }

            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Pay

    /// Paying opens the send flow at the requester's own address, and remembers the request id
    /// so the receipt can settle it.
    @Test func payingARequestOpensTheSendFlowAndRemembersTheRequest() {
        let store = rootStore()

        store.send(.chatRoom(.payRequestTapped(requestMessage(id: "req-1", amount: "0.5", memo: "Taxi"))))

        #expect(store.path == .sendCoordFlow)
        #expect(store.returnsToChatRoomAfterWalletFlow)
        #expect(store.chatSendContext?.conversationId == "conversation")
        #expect(store.chatSendContext?.requestId == "req-1")
        // Android prefills the memo from the request too (`PrefillSendData.All(memos:)`).
        #expect(store.sendCoordFlowState.sendFormState.memoState.text == "Taxi")
    }

    /// A plain Send ZEC settles nothing, so it must carry no request id — otherwise it would
    /// mark an unrelated request Paid.
    @Test func aPlainSendCarriesNoRequestId() {
        var state = Root.State.initial
        state.chatRoomState = ChatRoom.State(conversationId: "conversation")
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
        state.path = .chatRoom

        let store = Store(initialState: state) {
            Root()
        } withDependencies: {
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.mnemonic = .mock
            $0.sdkSynchronizer = .noOp
            $0.walletStorage = .noOp
            $0.zcashSDKEnvironment = .testnet
        }

        store.send(.chatRoom(.sendZecTapped))

        #expect(store.chatSendContext?.conversationId == "conversation")
        #expect(store.chatSendContext?.requestId == nil)
    }

    @Test func sendingToASharedAddressOpensTheSendFlow() {
        let store = rootStore()

        store.send(.chatRoom(.sendToAddressTapped(Self.peerAddress)))

        #expect(store.path == .sendCoordFlow)
        #expect(store.returnsToChatRoomAfterWalletFlow)
        #expect(store.chatSendContext?.requestId == nil)
    }

    // MARK: - Receipt

    @Test func aSuccessfulChatSendPostsAReceiptQuotingTheRequest() async throws {
        let receipts = LockIsolated<[(conversationId: String, payload: String)]>([])
        let store = rootStore(sentReceipts: receipts)

        store.send(.chatRoom(.payRequestTapped(requestMessage(id: "req-1", amount: "0.5"))))

        #expect(store.chatSendContext?.requestId == "req-1")

        store.send(
            .sendCoordFlow(
                .resolveSendResult(.success, confirmationState(amount: Zatoshi(50_000_000), txId: "abc123"))
            )
        )

        try await waitUntil { !receipts.value.isEmpty }

        let posted = try #require(receipts.value.first)

        #expect(receipts.value.count == 1)
        #expect(posted.conversationId == "conversation")

        let parsed = ChatTransactionReceipt.parse(posted.payload)

        #expect(parsed.requestId == "req-1")
        #expect(parsed.amount == Decimal(string: "0.5"))
        #expect(parsed.token == "ZEC")
        // The context is consumed exactly once.
        #expect(store.chatSendContext == nil)
    }

    /// Only a full success may notify the peer — a failed or pending send must post nothing.
    @Test func aFailedSendPostsNoReceipt() async throws {
        let receipts = LockIsolated<[(conversationId: String, payload: String)]>([])
        let store = rootStore(sentReceipts: receipts)

        store.send(.chatRoom(.payRequestTapped(requestMessage(id: "req-1", amount: "0.5"))))
        store.send(
            .sendCoordFlow(
                .resolveSendResult(.failure, confirmationState(amount: Zatoshi(50_000_000), txId: "abc123"))
            )
        )

        // The consumed context is the signal that the receipt case ran at all, so an empty
        // receipt list afterwards means "declined to post", not "not yet".
        try await waitUntil { store.chatSendContext == nil }

        #expect(receipts.value.isEmpty)
        // Still consumed, so it cannot attach to the next unrelated send.
        #expect(store.chatSendContext == nil)
    }

    /// Phase 12 regression: the send form and the swap form are now one screen, so a send opened
    /// from a chat room can be switched to swap mode and resolve through the very same case. That
    /// ZEC went to the swap provider's deposit address, not to the peer — posting a receipt would
    /// claim they were paid, and would flip a quoted request to Paid while it is still owed.
    @Test func aSwapResolvedFromAChatSendPostsNoReceipt() async throws {
        let receipts = LockIsolated<[(conversationId: String, payload: String)]>([])
        let store = rootStore(sentReceipts: receipts)

        store.send(.chatRoom(.payRequestTapped(requestMessage(id: "req-1", amount: "0.5"))))

        var swapConfirmation = confirmationState(amount: Zatoshi(50_000_000), txId: "abc123")
        swapConfirmation.type = .swap

        store.send(.sendCoordFlow(.resolveSendResult(.success, swapConfirmation)))

        // The consumed context proves the receipt case ran and declined, rather than not having run.
        try await waitUntil { store.chatSendContext == nil }

        #expect(receipts.value.isEmpty)
    }

    /// The cross-pay corridor spends ZEC to a provider too, so it is refused for the same reason.
    @Test func aCrossPayResolvedFromAChatSendPostsNoReceipt() async throws {
        let receipts = LockIsolated<[(conversationId: String, payload: String)]>([])
        let store = rootStore(sentReceipts: receipts)

        store.send(.chatRoom(.payRequestTapped(requestMessage(id: "req-1", amount: "0.5"))))

        var payConfirmation = confirmationState(amount: Zatoshi(50_000_000), txId: "abc123")
        payConfirmation.type = .pay

        store.send(.sendCoordFlow(.resolveSendResult(.success, payConfirmation)))

        try await waitUntil { store.chatSendContext == nil }

        #expect(receipts.value.isEmpty)
    }

    /// A send that never started from a chat posts nothing at all.
    @Test func aSendStartedOutsideAChatPostsNoReceipt() async throws {
        let receipts = LockIsolated<[(conversationId: String, payload: String)]>([])
        let store = rootStore(sentReceipts: receipts)

        store.send(.home(.sendTapped))
        store.send(
            .sendCoordFlow(
                .resolveSendResult(.success, confirmationState(amount: Zatoshi(50_000_000), txId: "abc123"))
            )
        )

        // There was never a context to consume, so there is no positive signal to wait for.
        // A short bounded wait gives a stray effect a fair chance to fire and be caught.
        try await waitUntil({ !receipts.value.isEmpty }, timeout: Swift.Duration.seconds(1))

        #expect(receipts.value.isEmpty)
    }

    // MARK: - View transaction

    /// A peer-supplied tx id that this wallet has never seen must not push a detail screen that
    /// would load forever — Android checks its own transaction list first.
    @Test func viewingAnUnknownTransactionReportsInsteadOfNavigating() {
        let store = rootStore()

        store.send(.chatRoom(.viewTransactionTapped("not-a-known-tx")))

        #expect(store.path == .chatRoom)
        #expect(store.chatRoomState.sendDidFail)
    }

    @Test func viewingAKnownTransactionOpensItsDetail() {
        let store = rootStore()
        let transaction = TransactionState(
            fee: Zatoshi(10_000),
            id: "known-tx",
            status: .paid,
            zecAmount: Zatoshi(100_000)
        )
        store.state.$transactions.withLock { $0 = [transaction] }

        store.send(.chatRoom(.viewTransactionTapped("known-tx")))

        #expect(store.path == .transactionsCoordFlow)
        #expect(store.transactionsCoordFlowState.transactionToOpen == "known-tx")
        // And closing it lands back on the room it was opened from.
        store.send(.transactionsCoordFlow(.transactionDetails(.closeDetailTapped)))

        #expect(store.path == .chatRoom)
    }
}
