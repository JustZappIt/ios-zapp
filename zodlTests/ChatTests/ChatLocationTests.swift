//
//  ChatLocationTests.swift
//  zodlTests
//
//  Location sharing: the `application/location` wire body against Android's
//  `ChatRoomVM.sendLocationMessage` / `LocationBubble.kt`, and the media sheet's Location tile
//  through permission, fix and send.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite struct ChatLocationWireTests {
    // MARK: - Encode (`sendLocationMessage`)

    /// What Android's `org.json` prints for the same three doubles: insertion order, no spaces,
    /// and an integral accuracy without a trailing `.0`.
    @Test func theBodyMatchesAndroidByteForByte() throws {
        let body = try #require(ChatLocation.json(latitude: 37.7749, longitude: -122.4194, accuracy: 20))

        #expect(body == #"{"latitude":37.7749,"longitude":-122.4194,"accuracy":20}"#)
    }

    @Test func fractionalValuesKeepTheirShortestDigits() throws {
        let body = try #require(ChatLocation.json(latitude: -33.8688, longitude: 151.2093, accuracy: 4.5))

        #expect(body == #"{"latitude":-33.8688,"longitude":151.2093,"accuracy":4.5}"#)
    }

    /// `JSONSerialization` raises an uncatchable exception on NaN, so a bad fix must never reach it.
    @Test func aNonFiniteOrOutOfRangeFixIsRefused() {
        #expect(ChatLocation.json(latitude: .nan, longitude: 0, accuracy: 5) == nil)
        #expect(ChatLocation.json(latitude: 0, longitude: .infinity, accuracy: 5) == nil)
        #expect(ChatLocation.json(latitude: 0, longitude: 0, accuracy: .nan) == nil)
        #expect(ChatLocation.json(latitude: 91, longitude: 0, accuracy: 5) == nil)
        #expect(ChatLocation.json(latitude: 0, longitude: -181, accuracy: 5) == nil)
    }

    // MARK: - Decode (`LocationBubble.kt`)

    /// Android writes `accuracy` from a `Float`, so its double carries float noise. The reader
    /// must take it as-is, and re-encoding must reproduce the same body.
    @Test func anAndroidAuthoredBodyRoundTrips() throws {
        let android = #"{"latitude":-33.8688,"longitude":151.2093,"accuracy":13.086999893188477}"#

        let location = try #require(ChatLocation.parse(android))

        #expect(location.latitude == -33.8688)
        #expect(location.longitude == 151.2093)
        #expect(location.accuracy == 13.086999893188477)
        #expect(location.coordinateText == "-33.868800, 151.209300")
        #expect(
            ChatLocation.json(
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy ?? 0
            ) == android
        )
    }

    /// `optDouble` coerces a quoted number, and Android never reads `accuracy` back.
    @Test func quotedCoordinatesParseAndAccuracyIsOptional() throws {
        let location = try #require(ChatLocation.parse(#"{"latitude":"1.5","longitude":"-2.25"}"#))

        #expect(location == ChatLocation(latitude: 1.5, longitude: -2.25, accuracy: nil))
    }

    /// Anything that is not a real position degrades to the text bubble rather than Android's
    /// "NaN, NaN".
    @Test func malformedOrLegacyBodiesDoNotParse() {
        let bodies = [
            "",
            "{}",
            "not json",
            "[1, 2]",
            #"{"latitude":12.5}"#,
            #"{"latitude":"north","longitude":1}"#,
            #"{"latitude":true,"longitude":false}"#,
            #"{"latitude":91,"longitude":0}"#,
            #"{"latitude":0,"longitude":180.5}"#
        ]

        for body in bodies {
            #expect(ChatLocation.parse(body) == nil, "\(body)")
        }
    }

    @Test func openInMapsPinsTheSharedPoint() throws {
        let url = try #require(ChatLocation(latitude: 37.7749, longitude: -122.4194, accuracy: nil).mapsURL)

        #expect(url.absoluteString == "https://maps.apple.com/?ll=37.774900,-122.419400&q=37.774900,-122.419400")
    }

    // MARK: - Classification and previews

    @Test func theDeclaredTypeClassifiesALocation() {
        let message = ZMMessage(
            id: "1",
            conversationId: "c",
            senderId: "peer",
            content: #"{"latitude":1,"longitude":2,"accuracy":3}"#,
            contentType: ChatContentType.location,
            isFromMe: false
        )

        #expect(ChatContentType.location == "application/location")
        #expect(ChatMessageKind.of(message) == .location)
    }

    /// The core keeps a location's raw body (truncated to 100 characters) as the cold-load preview.
    @Test func aColdLoadedLocationPreviewsAsLocation() {
        let body = #"{"latitude":-33.8688,"longitude":151.2093,"accuracy":13.086999893188477}"#

        #expect(ChatPreviewSentinel.jsonLabel(for: body) == String(localizable: .chatListLocationPlaceholder))
        #expect(
            ChatPreviewSentinel.jsonLabel(for: String(body.prefix(30)))
                == String(localizable: .chatListLocationPlaceholder)
        )
        #expect(ChatPreviewSentinel.label(for: "[Location]") == String(localizable: .chatListLocationPlaceholder))
    }
}

@MainActor
@Suite struct ChatLocationFlowTests {
    private let fix = LocationFix(latitude: 37.7749, longitude: -122.4194, accuracy: 20)

    /// Tile → sheet closes → permission → fix → `application/location` send.
    @Test func grantedPermissionSendsAndroidsBody() async {
        let sent = LockIsolated<[String]>([])
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.location.isAuthorized = { false }
            $0.location.requestAuthorization = { true }
            $0.location.currentLocation = { [fix] in fix }
            $0.zappMessaging.sendLocation = { conversationId, payload in
                sent.withValue { $0.append(payload) }

                return ZMMessage(
                    id: "location-1",
                    conversationId: conversationId,
                    senderId: "me",
                    content: payload,
                    contentType: ChatContentType.location,
                    isFromMe: true
                )
            }
        }

        await store.send(.attachTapped) {
            $0.showsAttachmentSheet = true
        }

        await store.send(.attachMediaTapped) {
            $0.attachmentPage = .media
        }

        await store.send(.shareLocationTapped) {
            $0.pendingLocationShare = true
            $0.showsAttachmentSheet = false
        }

        await store.send(.attachmentSheetClosed) {
            $0.pendingLocationShare = false
            $0.attachmentPage = .actions
        }

        await store.receive(\.locationAuthorizationResolved) {
            $0.isSendingMedia = true
        }

        store.exhaustivity = .off
        await store.receive(\.mediaSendSucceeded)

        #expect(sent.value == [#"{"latitude":37.7749,"longitude":-122.4194,"accuracy":20}"#])
        #expect(!store.state.isSendingMedia)
        #expect(!store.state.sendDidFail)
        #expect(store.state.messages.last?.contentType == ChatContentType.location)
    }

    /// Android's "Location permission required", plus the Settings deep link iOS offers for a
    /// refusal it cannot re-prompt.
    @Test func deniedPermissionSurfacesTheRefusalAndSendsNothing() async {
        let fixes = LockIsolated(0)
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.location.isAuthorized = { false }
            $0.location.requestAuthorization = { false }
            $0.location.currentLocation = { [fix] in
                fixes.withValue { $0 += 1 }
                return fix
            }
        }

        await store.send(.shareLocationTapped) {
            $0.pendingLocationShare = true
        }

        await store.send(.attachmentSheetClosed) {
            $0.pendingLocationShare = false
        }

        await store.receive(\.locationAuthorizationResolved) {
            $0.sendDidFail = true
            $0.sendFailureMessage = String(localizable: .chatRoomLocationPermissionRequired)
        }

        #expect(fixes.value == 0)
        #expect(ChatSendFailure.offersSettings(store.state.sendFailureMessage))
    }

    /// No fix in time: Android's "Could not get location", and the composer is usable again.
    @Test func aTimedOutFixReportsCouldNotGetLocation() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.location.isAuthorized = { true }
            $0.location.currentLocation = { throw LocationFailure.unavailable }
        }

        await store.send(.shareLocationTapped) {
            $0.pendingLocationShare = true
        }

        await store.send(.attachmentSheetClosed) {
            $0.pendingLocationShare = false
        }

        await store.receive(\.locationAuthorizationResolved) {
            $0.isSendingMedia = true
        }

        await store.receive(\.attachmentFailed) {
            $0.isSendingMedia = false
            $0.sendDidFail = true
            $0.sendFailureMessage = String(localizable: .chatRoomLocationUnavailable)
        }

        #expect(store.state.sendFailureMessage == "Could not get location")
        #expect(!ChatSendFailure.offersSettings(store.state.sendFailureMessage))
    }

    @Test func otherCoreLocationErrorsCarryTheirReason() {
        #expect(ChatRoom.failureMessage(for: LocationFailure.failed("Boom")) == "Location error: Boom")
        #expect(
            ChatRoom.failureMessage(for: LocationFailure.notAuthorized)
                == String(localizable: .chatRoomLocationPermissionRequired)
        )
    }
}
