//
//  ChatWalletHandoffTests.swift
//  zodlTests
//
//  Phase 5 — a wallet flow opened from a chat room has to unwind back onto that room, while
//  every OTHER entry into the same flows keeps unwinding to the tabs. `Root.path` holds one
//  destination at a time, so that "way back" is a single remembered flag — and a flag left set
//  by one entry point would silently hijack the next one. These tests pin both directions.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Serialized: drives a Root store sharing process-global `@Shared` state.
@Suite(.serialized) @MainActor struct ChatWalletHandoffTests {
    private static let peerAddress = "tmP3uLtGx5GPddkq8a6ddmXhqJJ3vy6tpTE"

    /// A Root sitting in a chat room, optionally one where the peer already shared an address
    /// (which is what makes Send ZEC resolve a recipient instead of falling out to the scanner).
    private func rootStore(peerSharedAddress: Bool) -> StoreOf<Root> {
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

    private func payTabStore() -> StoreOf<Root> {
        store(with: .initial)
    }

    /// The send flow validates the prefilled address, so `derivationTool` has to be live rather
    /// than the unimplemented test default.
    private func store(with state: Root.State) -> StoreOf<Root> {
        Store(initialState: state) {
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
    }

    // MARK: - Send flow

    @Test func aSendStartedFromAChatRoomUnwindsBackOntoThatRoom() {
        let store = rootStore(peerSharedAddress: true)

        store.send(.chatRoom(.sendZecTapped))

        #expect(store.path == .sendCoordFlow)
        #expect(store.returnsToChatRoomAfterWalletFlow)

        store.send(.sendCoordFlow(.sendForm(.dismissRequired)))

        #expect(store.path == .chatRoom)
        #expect(!store.returnsToChatRoomAfterWalletFlow)
    }

    /// The regression this guards: Send from the Pay tab used to share one case group with the
    /// chat send's dismissal. It must still unwind to the tabs.
    @Test func aSendStartedFromThePayTabStillUnwindsToTheTabs() {
        let store = payTabStore()

        store.send(.home(.sendTapped))

        #expect(store.path == .sendCoordFlow)
        #expect(!store.returnsToChatRoomAfterWalletFlow)

        store.send(.sendCoordFlow(.sendForm(.dismissRequired)))

        #expect(store.path == nil)
    }

    /// Send-again is the third entry point, and it must not inherit a flag left set by an
    /// earlier chat send.
    @Test func sendAgainClearsAChatFlagLeftByAnEarlierChatSend() {
        let store = rootStore(peerSharedAddress: true)

        store.send(.chatRoom(.sendZecTapped))

        #expect(store.returnsToChatRoomAfterWalletFlow)

        store.send(
            .sendAgainRequested(
                TransactionState(fee: Zatoshi(10_000), id: "tx-id", status: .sending, zecAmount: Zatoshi(100_000))
            )
        )

        #expect(store.path == .sendCoordFlow)
        #expect(!store.returnsToChatRoomAfterWalletFlow)

        store.send(.sendCoordFlow(.sendForm(.dismissRequired)))

        #expect(store.path == nil)
    }

    // MARK: - Scan flow

    /// Send ZEC with no known peer address falls out to the scanner, and cancelling the scanner
    /// has to land back on the room rather than dropping the user onto the tabs.
    @Test func aScanStartedFromAChatRoomUnwindsBackOntoThatRoom() {
        let store = rootStore(peerSharedAddress: false)

        store.send(.chatRoom(.scanWalletAddressTapped))

        #expect(store.path == .scanCoordFlow)
        #expect(store.returnsToChatRoomAfterWalletFlow)

        store.send(.scanCoordFlow(.scan(.cancelTapped)))

        #expect(store.path == .chatRoom)
        #expect(!store.returnsToChatRoomAfterWalletFlow)
    }

    @Test func aScanStartedFromThePayTabStillUnwindsToTheTabs() {
        let store = payTabStore()

        store.send(.home(.scanTapped))

        #expect(!store.returnsToChatRoomAfterWalletFlow)

        store.send(.scanCoordFlow(.scan(.cancelTapped)))

        #expect(store.path == nil)
    }
}
