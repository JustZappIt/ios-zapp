//
//  ChatAttachmentParityTests.swift
//  zodlTests
//
//  Phase 5 — composer attachment menu. The wire-format assertions here are the important
//  ones: a wallet-address message that does not match Android byte-for-byte renders as an
//  unknown bubble on the peer.
//

import ComposableArchitecture
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
import ZappMessaging
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// Serialized: the share-address path reads the process-wide `zashiWalletAccount` shared store.
@Suite(.serialized) struct ChatAttachmentParityTests {
    private let unifiedAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    private func zashiAccount() throws -> WalletAccount {
        var account = WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: 0, count: 16)),
                name: "Zodl",
                keySource: nil,
                seedFingerprint: nil,
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
        account.defaultUA = try UnifiedAddress(encoding: unifiedAddress, network: .testnet)

        return account
    }

    private func walletAddressMessage(id: String, content: String, isFromMe: Bool) -> ZMMessage {
        ZMMessage(
            id: id,
            conversationId: "conversation",
            senderId: isFromMe ? "me" : "peer",
            content: content,
            contentType: ChatContentType.walletAddress,
            timestamp: Date(timeIntervalSince1970: 100),
            isFromMe: isFromMe
        )
    }

    // MARK: - Sheet choreography

    @MainActor @Test func attachOpensTheActionSheetAndAttachMediaSwapsThePage() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        }

        await store.send(.attachTapped) {
            $0.attachmentPage = .actions
            $0.showsAttachmentSheet = true
        }

        await store.send(.attachMediaTapped) {
            $0.attachmentPage = .media
        }
    }

    /// A picker can only be presented once the sheet is off screen, so the choice is parked
    /// and promoted from the sheet's dismissal callback.
    @MainActor @Test func choosingGalleryParksThePickerUntilTheSheetHasClosed() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        }

        await store.send(.attachTapped) {
            $0.attachmentPage = .actions
            $0.showsAttachmentSheet = true
        }

        await store.send(.chooseMediaTapped) {
            $0.pendingAttachment = .photos
            $0.showsAttachmentSheet = false
        }

        #expect(!store.state.showsPhotosPicker)

        await store.send(.attachmentSheetClosed) {
            $0.pendingAttachment = nil
            $0.showsPhotosPicker = true
        }
    }

    @MainActor @Test func cameraAsksForPermissionAndPresentsOnceGranted() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.cameraCapture.isAvailable = { true }
            $0.cameraCapture.isAuthorized = { false }
            $0.cameraCapture.requestAuthorization = { true }
        }

        await store.send(.takePhotoTapped) {
            $0.pendingAttachment = .camera
            $0.showsAttachmentSheet = false
        }

        await store.send(.attachmentSheetClosed) {
            $0.pendingAttachment = nil
        }

        await store.receive(\.cameraAuthorizationResolved) {
            $0.showsCamera = true
        }
    }

    @MainActor @Test func refusedCameraPermissionSurfacesTheRefusalInsteadOfOpeningTheCamera() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.cameraCapture.isAvailable = { true }
            $0.cameraCapture.isAuthorized = { false }
            $0.cameraCapture.requestAuthorization = { false }
        }

        await store.send(.takePhotoTapped) {
            $0.pendingAttachment = .camera
            $0.showsAttachmentSheet = false
        }

        await store.send(.attachmentSheetClosed) {
            $0.pendingAttachment = nil
        }

        await store.receive(\.cameraAuthorizationResolved) {
            $0.sendDidFail = true
            $0.sendFailureMessage = String(localizable: .chatRoomCameraPermissionRequired)
        }

        #expect(!store.state.showsCamera)
    }

    // MARK: - Share address (wire format)

    /// THE wire-format guard. Android's `shareWalletAddress()` sends the unified address as the
    /// message BODY under `application/wallet-address` — not JSON, not a new IPC type. Its
    /// `WalletAddressBubble` reads `message.content` straight back out.
    @MainActor @Test func shareAddressPostsTheUnifiedAddressUnderAndroidsContentType() async throws {
        let sent = LockIsolated<[(conversationId: String, address: String)]>([])
        let account = try zashiAccount()

        var state = ChatRoom.State(conversationId: "conversation")
        state.$zashiWalletAccount.withLock { $0 = account }

        let posted = walletAddressMessage(id: "posted", content: unifiedAddress, isFromMe: true)

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendWalletAddress = { conversationId, address in
                sent.withValue { $0.append((conversationId, address)) }
                return posted
            }
        }
        store.exhaustivity = .off

        await store.send(.attachTapped)
        await store.send(.shareAddressTapped)
        await store.receive(\.messageReceived)

        #expect(sent.value.count == 1)
        #expect(sent.value.first?.conversationId == "conversation")
        #expect(sent.value.first?.address == unifiedAddress)
        #expect(!store.state.showsAttachmentSheet)
        #expect(store.state.messages.first?.contentType == "application/wallet-address")
        #expect(store.state.messages.first?.content == unifiedAddress)
    }

    @MainActor @Test func shareAddressWithoutAWalletAccountFailsLoudlyAndSendsNothing() async {
        let calls = LockIsolated(0)

        var state = ChatRoom.State(conversationId: "conversation")
        state.$zashiWalletAccount.withLock { $0 = nil }

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendWalletAddress = { _, address in
                calls.withValue { $0 += 1 }
                return ZMMessage(id: "x", conversationId: "conversation", senderId: "me", content: address, isFromMe: true)
            }
        }

        await store.send(.shareAddressTapped) {
            $0.showsAttachmentSheet = false
            $0.sendDidFail = true
            $0.sendFailureMessage = String(localizable: .chatRoomShareAddressFailed)
        }

        #expect(calls.value == 0)
    }

    // MARK: - Send ZEC / scan

    @MainActor @Test func sendZecFallsBackToTheScannerWhenNoPeerAddressIsKnown() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        }

        await store.send(.attachTapped) {
            $0.attachmentPage = .actions
            $0.showsAttachmentSheet = true
        }

        await store.send(.sendZecTapped) {
            $0.showsAttachmentSheet = false
        }

        await store.receive(\.scanWalletAddressTapped)
    }

    @MainActor @Test func sendZecKeepsRoutingToRootWhenThePeerSharedAnAddress() async {
        var state = ChatRoom.State(conversationId: "conversation")
        state.messages = [walletAddressMessage(id: "peer-1", content: unifiedAddress, isFromMe: false)]

        let store = TestStore(initialState: state) {
            ChatRoom()
        }

        await store.send(.attachTapped) {
            $0.attachmentPage = .actions
            $0.showsAttachmentSheet = true
        }

        // No follow-up action: Root reads `resolvedPeerWalletAddress` and opens the send flow.
        await store.send(.sendZecTapped) {
            $0.showsAttachmentSheet = false
        }

        #expect(store.state.resolvedPeerWalletAddress == unifiedAddress)
    }

    @MainActor @Test func theNewestPeerSharedAddressWinsAndOurOwnIsIgnored() {
        var state = ChatRoom.State(conversationId: "conversation")
        state.messages = [
            walletAddressMessage(id: "peer-old", content: "old-peer-address", isFromMe: false),
            walletAddressMessage(id: "peer-new", content: "new-peer-address", isFromMe: false),
            walletAddressMessage(id: "mine", content: "my-own-address", isFromMe: true)
        ]

        #expect(state.peerSharedWalletAddress == "new-peer-address")
        #expect(state.resolvedPeerWalletAddress == "new-peer-address")
    }

    @MainActor @Test func aSavedContactAddressBacksTheSendWhenNothingWasSharedInChat() {
        var state = ChatRoom.State(conversationId: "conversation")
        state.conversation = ZMConversation(
            id: "conversation",
            type: .direct,
            participantIds: ["peerkey"],
            displayName: "Peer"
        )
        state.$chatContacts.withLock {
            $0 = ChatContacts(
                lastUpdated: Date(timeIntervalSince1970: 0),
                version: ChatContacts.Constants.version,
                contacts: [
                    ChatContact(publicKey: "peerkey", name: "Peer", address: "saved-contact-address")
                ]
            )
        }

        #expect(state.peerSharedWalletAddress == nil)
        #expect(state.resolvedPeerWalletAddress == "saved-contact-address")
    }

    // MARK: - Gallery encoding

    /// Android's `sendMediaFromUri` ships a picked GIF from its cache untouched under
    /// `MimeTypes.GIF`. Re-encoding it would hand the peer a single frozen frame.
    @Test func aPickedGifIsForwardedAnimatedRatherThanFlattenedToAStill() throws {
        // 1x1 transparent GIF89a.
        let gif = try #require(
            Data(
                base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
            )
        )

        let encoded = try ChatMediaEncoder.encode(gif, supportedTypes: [UTType.gif])

        defer { try? FileManager.default.removeItem(atPath: encoded.path) }

        #expect(encoded.contentType == "image/gif")
        #expect(encoded.contentType == ChatContentType.gif)
        #expect(try Data(contentsOf: URL(fileURLWithPath: encoded.path)) == gif)
    }

    /// Every non-GIF still is normalised to JPEG — so a peer told `image/jpeg` never receives
    /// HEIC bytes, and so no source can skip the re-encode. The PNG passthrough this used to
    /// assert was removed deliberately: forwarding PNG verbatim let a highly-compressed source
    /// bypass the output bound and reach the worklet as a multi-megabyte allocation.
    @Test func everyNonGifStillIsNormalisedToJpeg() throws {
        let png = try #require(UIImage(systemName: "circle")?.pngData())

        let asPNG = try ChatMediaEncoder.encode(png, supportedTypes: [UTType.png])
        defer { try? FileManager.default.removeItem(atPath: asPNG.path) }
        #expect(asPNG.contentType == "image/jpeg")

        let asJPEG = try ChatMediaEncoder.encode(png, supportedTypes: [UTType.heic])
        defer { try? FileManager.default.removeItem(atPath: asJPEG.path) }
        #expect(asJPEG.contentType == "image/jpeg")
    }

    // MARK: - File encoding

    /// A document is forwarded byte-for-byte and its name rides in the CAPTION, which is where
    /// Android's `sendFileFromUri` puts it and where its `FileBubble` reads it from.
    @Test func fileEncodingPreservesBytesAndCarriesTheNameAndMimeType() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("zapp-test-\(UUID().uuidString).pdf")
        let payload = Data("not really a pdf".utf8)
        try payload.write(to: source)

        defer { try? FileManager.default.removeItem(at: source) }

        let encoded = try ChatFileEncoder.encode(source)

        defer { try? FileManager.default.removeItem(atPath: encoded.path) }

        #expect(encoded.contentType == "application/pdf")
        #expect(encoded.fileName == source.lastPathComponent)
        #expect(encoded.thumbnail == nil)
        #expect(try Data(contentsOf: URL(fileURLWithPath: encoded.path)) == payload)
    }

    @Test func anUnknownExtensionFallsBackToOctetStreamRatherThanGuessing() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("zapp-test-\(UUID().uuidString).zappzapp")
        try Data("payload".utf8).write(to: source)

        defer { try? FileManager.default.removeItem(at: source) }

        let encoded = try ChatFileEncoder.encode(source)

        defer { try? FileManager.default.removeItem(atPath: encoded.path) }

        #expect(encoded.contentType == "application/octet-stream")
    }
}
