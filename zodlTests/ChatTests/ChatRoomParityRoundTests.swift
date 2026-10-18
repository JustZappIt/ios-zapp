//
//  ChatRoomParityRoundTests.swift
//  zodlTests
//
//  Android parity round for the Chats tab: the connection chips and the always-on room subtitle
//  (`ChatRoomVM` / `ChatListVM`), incoming location messages, and the identity-setup fallback.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal
import ZappMessaging

@Suite(.serialized) struct ChatRoomParityRoundTests {
    private static func messagingState(
        phase: ZappMessagingState.Phase = .ready,
        isOnline: Bool = true,
        dhtHealth: String = "healthy",
        online: Set<String> = [],
        presenceVisible: Bool = true
    ) -> ZappMessagingState {
        var state = ZappMessagingState(phase: phase)
        state.isOnline = isOnline
        state.dhtHealth = dhtHealth
        state.onlineConversationIds = online
        state.presenceVisible = presenceVisible
        return state
    }

    // MARK: - Connection status and room subtitle

    @Test func theConnectionStatusFollowsAndroidsFourStates() {
        #expect(Self.messagingState(phase: .initializing).connectionStatus == .connecting)
        #expect(Self.messagingState(phase: .failed("boot")).connectionStatus == .error)
        #expect(Self.messagingState(isOnline: false).connectionStatus == .disconnected)
        #expect(Self.messagingState().connectionStatus == .connected)
    }

    /// Android always shows a subtitle; iOS used to show one only while offline.
    @Test func theRoomSubtitleIsAlwaysPresent() {
        #expect(Self.messagingState(phase: .initializing).roomSubtitle(for: "c") == String(localizable: .chatRoomSubtitleConnecting))
        #expect(Self.messagingState(isOnline: false).roomSubtitle(for: "c") == String(localizable: .chatRoomSubtitleOffline))
        #expect(Self.messagingState(phase: .failed("x")).roomSubtitle(for: "c") == String(localizable: .chatRoomSubtitleError))
        #expect(Self.messagingState().roomSubtitle(for: "c") == String(localizable: .chatRoomSubtitleWaitingForPeer))
        #expect(Self.messagingState(online: ["c"]).roomSubtitle(for: "c") == String(localizable: .chatRoomSubtitlePeerOnline))
        #expect(
            Self.messagingState(dhtHealth: "critical").roomSubtitle(for: "c")
                == String(localizable: .chatRoomSubtitleDhtUnreachable)
        )
        #expect(
            Self.messagingState(dhtHealth: "degraded").roomSubtitle(for: "c")
                == String(localizable: .chatRoomSubtitleDhtDegraded)
        )
    }

    /// With our own presence hidden, a reachable peer reads as "P2P connected", never "online".
    @Test func hiddenPresenceStillReportsAReachablePeer() {
        let state = Self.messagingState(online: ["c"], presenceVisible: false)

        #expect(state.roomSubtitle(for: "c") == String(localizable: .chatRoomSubtitleP2pConnected))
    }

    @Test func theRoomRendersTheSubtitleFromTheMessagingState() {
        var room = ChatRoom.State(conversationId: "c")
        room.messagingState = Self.messagingState(online: ["c"])

        #expect(room.subtitle == String(localizable: .chatRoomSubtitlePeerOnline))
    }

    // MARK: - Location

    @Test func anIncomingLocationIsItsOwnKind() {
        let message = ZMMessage(
            id: "1",
            conversationId: "c",
            senderId: "peer",
            content: #"{"latitude":40.7128,"longitude":-74.006}"#,
            contentType: ChatContentType.location,
            isFromMe: false
        )

        #expect(ChatMessageKind.of(message) == .location)
        #expect(ChatLocation.parse(message.content).coordinates == "40.712800, -74.006000")
        #expect(ChatLocation.parse(message.content).mapsURL?.host == "maps.apple.com")
    }

    /// Android's `optDouble`: a malformed body degrades to 0, 0 rather than failing the row.
    @Test func aMalformedLocationDegradesToZero() {
        #expect(ChatLocation.parse("not json") == ChatLocation(latitude: 0, longitude: 0))
    }

    @Test func aColdLoadedLocationPreviewReadsLocationNotPayment() {
        #expect(
            ChatPreviewSentinel.jsonLabel(for: #"{"latitude":1.5,"longitude":2.5}"#)
                == String(localizable: .chatListLocationPlaceholder)
        )
    }

    // MARK: - Identity setup

    @MainActor @Test func anInvalidNameExplainsTheRulesOnlyOnSubmit() async {
        var state = ChatIdentitySetup.State()
        state.messagingState = ZappMessagingState(phase: .needsIdentity)
        let store = TestStore(initialState: state) {
            ChatIdentitySetup()
        }

        await store.send(.displayNameChanged("ab")) {
            $0.displayName = "ab"
        }
        await store.send(.continueTapped) {
            $0.showsNameRulesError = true
        }
        await store.send(.displayNameChanged("abc")) {
            $0.displayName = "abc"
            $0.showsNameRulesError = false
        }
    }

    @MainActor @Test func aValidNameAfterAFailedDeriveIsRetried() async {
        let names = LockIsolated<[String]>([])
        let retries = LockIsolated(0)
        var state = ChatIdentitySetup.State()
        state.messagingState = ZappMessagingState(phase: .needsIdentity)
        state.messagingState.identityErrorCode = "derive_failed"
        state.displayName = "alice"
        let store = TestStore(initialState: state) {
            ChatIdentitySetup()
        } withDependencies: {
            $0.zappMessaging.setDisplayName = { name in names.withValue { $0.append(name) } }
            $0.zappMessaging.retryIdentityDerivation = { retries.withValue { $0 += 1 } }
        }

        await store.send(.continueTapped)

        #expect(names.value == ["alice"])
        #expect(retries.value == 1)
    }

    @MainActor @Test func copyErrorDetailsPutsTheDiagnosticOnTheClipboard() async {
        let copied = LockIsolated<[String]>([])
        var state = ChatIdentitySetup.State()
        state.messagingState = ZappMessagingState(phase: .needsIdentity)
        state.messagingState.identityErrorCode = "derive_failed"
        let store = TestStore(initialState: state) {
            ChatIdentitySetup()
        } withDependencies: {
            $0.pasteboard.setString = { value in copied.withValue { $0.append(value.data) } }
        }

        await store.send(.copyErrorDetailsTapped)

        #expect(copied.value.count == 1)
        #expect(copied.value.first?.contains("code: derive_failed") == true)
        #expect(copied.value.first?.contains("when: chat-identity setup") == true)
    }
}
