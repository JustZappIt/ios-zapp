//
//  ChatGIFPickerTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite struct ChatGIFPickerTests {
    /// A 1x1 GIF89a, so the encoder's byte sniffing and ImageIO thumbnailing both see real input.
    private static let tinyGIF = Data(
        base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
    ) ?? Data()

    private struct DownloadFailure: Error { }

    private static func response(_ items: [[String: Any]]) -> Data {
        let payload: [String: Any] = ["result": true, "data": ["data": items]]

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func gifItem(_ sizes: [String: Any], slug: String = "a-cat") -> [String: Any] {
        ["id": 8_041_071_659_142_944, "slug": slug, "title": "a cat", "type": "gif", "file": sizes]
    }

    private static func size(_ url: String, bytes: Int, width: Int = 200, height: Int = 100) -> [String: Any] {
        ["gif": ["url": url, "width": width, "height": height, "size": bytes]]
    }

    // MARK: Rendition selection

    /// `md` and `hd` are the same pixel size and differ only in encoding, so the cheaper one wins
    /// rather than the biggest that merely fits.
    @Test func parsePrefersTheCheaperFullSizeRendition() throws {
        let data = Self.response([
            Self.gifItem([
                "hd": Self.size("https://media.klipy.com/hd.gif", bytes: 4_001_918, width: 498, height: 498),
                "md": Self.size("https://media.klipy.com/md.gif", bytes: 3_721_260, width: 498, height: 498),
                "sm": Self.size("https://media.klipy.com/sm.gif", bytes: 314_884, width: 220, height: 220),
                "xs": Self.size("https://media.klipy.com/xs.gif", bytes: 71_468, width: 90, height: 90)
            ])
        ])

        let gifs = try KlipyGIFCatalog.parse(data, maxSendBytes: 8 * 1024 * 1024)
        let gif = try #require(gifs.first)

        #expect(gifs.count == 1)
        #expect(gif.sendURL == "https://media.klipy.com/md.gif")
        #expect(gif.previewURL == "https://media.klipy.com/sm.gif")
        #expect(gif.width == 220)
        #expect(gif.height == 220)
        #expect(gif.id == "a-cat")
        #expect(gif.title == "a cat")
    }

    @Test func parseFallsBackWhenEveryLargeRenditionIsOversized() throws {
        let data = Self.response([
            Self.gifItem([
                "hd": Self.size("https://media.klipy.com/hd.gif", bytes: 20_000_000),
                "md": Self.size("https://media.klipy.com/md.gif", bytes: 12_000_000),
                "xs": Self.size("https://media.klipy.com/xs.gif", bytes: 400_000)
            ])
        ])

        let gif = try #require(try KlipyGIFCatalog.parse(data, maxSendBytes: 8 * 1024 * 1024).first)

        #expect(gif.sendURL == "https://media.klipy.com/xs.gif")
    }

    @Test func parseDecodesTheInlineBlurPreview() throws {
        var item = Self.gifItem(["md": Self.size("https://media.klipy.com/md.gif", bytes: 100)])
        item["blur_preview"] = "data:image/jpeg;base64,\(Self.tinyGIF.base64EncodedString())"

        let gif = try #require(try KlipyGIFCatalog.parse(Self.response([item])).first)

        #expect(gif.blurPreview == Self.tinyGIF)
    }

    /// The blur preview is third-party bytes held for every visible cell, so a link, an unbounded
    /// payload, or anything that is not an inline image is refused rather than decoded.
    @Test func parseRefusesAnUnreasonableBlurPreview() {
        #expect(KlipyGIFCatalog.blurPreview(nil) == nil)
        #expect(KlipyGIFCatalog.blurPreview("https://evil.example/pixel.jpg") == nil)
        #expect(KlipyGIFCatalog.blurPreview("data:text/html;base64,PGI+") == nil)
        #expect(KlipyGIFCatalog.blurPreview("data:image/jpeg;base64,\(String(repeating: "A", count: 9000))") == nil)
    }

    @Test func parseDropsResultsWhoseRenditionsAreAllOversized() throws {
        let data = Self.response([
            Self.gifItem(["hd": Self.size("https://media.klipy.com/hd.gif", bytes: 20_000_000)])
        ])

        #expect(try KlipyGIFCatalog.parse(data, maxSendBytes: 8 * 1024 * 1024).isEmpty)
    }

    /// Klipy funds the free tier by injecting adverts into the same result array. They arrive as
    /// `content` markup rather than a `file`, and the picker must only ever show real GIFs.
    @Test func parseDropsInjectedAdverts() throws {
        let data = Self.response([
            ["type": "ad", "content": "<div>buy this</div>", "width": 200, "height": 100],
            Self.gifItem(["xs": Self.size("https://media.klipy.com/xs.gif", bytes: 100)])
        ])

        let gifs = try KlipyGIFCatalog.parse(data, maxSendBytes: 8 * 1024 * 1024)

        #expect(gifs.count == 1)
        #expect(gifs.first?.sendURL == "https://media.klipy.com/xs.gif")
    }

    /// The renditions are third-party URLs, so they go through the same screening a link preview
    /// gets rather than being fetched because Klipy named them.
    @Test func parseRejectsRenditionsPointingSomewherePrivate() throws {
        let data = Self.response([
            Self.gifItem([
                "hd": Self.size("http://127.0.0.1/hd.gif", bytes: 100),
                "xs": Self.size("https://192.168.1.4/xs.gif", bytes: 100)
            ])
        ])

        #expect(try KlipyGIFCatalog.parse(data, maxSendBytes: 8 * 1024 * 1024).isEmpty)
    }

    @Test func parseRejectsAnUnrecognisedPayload() {
        #expect(throws: KlipyGIFError.badResponse) {
            try KlipyGIFCatalog.parse(Data("not json".utf8))
        }
    }

    @Test func parseKeepsResultsWithNoDeclaredSize() throws {
        let data = Self.response([
            Self.gifItem(["hd": ["gif": ["url": "https://media.klipy.com/hd.gif", "width": 10, "height": 5]]])
        ])

        let gif = try #require(try KlipyGIFCatalog.parse(data, maxSendBytes: 8 * 1024 * 1024).first)

        #expect(gif.sendURL == "https://media.klipy.com/hd.gif")
        #expect(gif.aspectRatio == 2)
    }

    @Test func endpointRefusesToBuildWithoutAKey() {
        guard KlipyGIFCatalog.apiKey == nil else { return }

        #expect(throws: KlipyGIFError.notConfigured) {
            try KlipyGIFCatalog.endpoint(path: "search", query: "cat", customerId: "anon")
        }
    }

    /// The safety filter is the one query parameter whose absence is invisible until something
    /// unwanted is already on screen in a chat.
    @Test func endpointAlwaysAsksForTheStrictestSafetyFilter() throws {
        guard KlipyGIFCatalog.apiKey != nil else { return }

        let url = try KlipyGIFCatalog.endpoint(path: "search", query: "cat", customerId: "anon")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let value: (String) -> String? = { name in items.first { $0.name == name }?.value }

        #expect(url.path.hasSuffix("/gifs/search"))
        #expect(value("content_filter") == "high")
        #expect(value("format_filter") == "gif")
        #expect(value("q") == "cat")
        #expect(value("customer_id") == "anon")
    }

    // MARK: Picker reducer

    @MainActor @Test func typingDebouncesIntoOneSearch() async {
        let searches = LockIsolated<[String]>([])
        let clock = TestClock()
        let store = TestStore(initialState: ChatGIFPicker.State()) {
            ChatGIFPicker()
        } withDependencies: {
            $0.continuousClock = clock
            $0.klipyGIF.search = { query in
                searches.withValue { $0.append(query) }
                return [KlipyGIF(id: "1", title: "", previewURL: "p", sendURL: "s", width: 2, height: 1, blurPreview: nil)]
            }
        }
        store.exhaustivity = .off

        await store.send(.queryChanged("ca"))
        await store.send(.queryChanged("cat"))
        await clock.advance(by: .milliseconds(350))

        await store.receive(\.reload)
        await store.receive(\.resultsLoaded)

        #expect(searches.value == ["cat"])
        #expect(store.state.results.count == 1)
        #expect(!store.state.isLoading)
    }

    @MainActor @Test func aFailedSearchSurfacesInsteadOfShowingAnEmptyGrid() async {
        let store = TestStore(initialState: ChatGIFPicker.State()) {
            ChatGIFPicker()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.klipyGIF.trending = { throw KlipyGIFError.badResponse }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.reload)
        await store.receive(\.loadFailed)

        #expect(store.state.didFail)
        #expect(!store.state.isLoading)
        #expect(!store.state.isEmpty)
    }

    @MainActor @Test func tappingAGifDelegatesTheSelection() async {
        let gif = KlipyGIF(id: "1", title: "", previewURL: "p", sendURL: "s", width: 2, height: 1, blurPreview: nil)
        let store = TestStore(initialState: ChatGIFPicker.State()) {
            ChatGIFPicker()
        }
        store.exhaustivity = .off

        await store.send(.gifTapped(gif))
        await store.receive(\.delegate)
    }

    // MARK: Room wiring

    @MainActor @Test func choosingAGifDownloadsItAndSendsItAsAnAnimatedGif() async throws {
        let url = ChatMediaTemporaryFiles.makeURL(pathExtension: "gif")
        try Self.tinyGIF.write(to: url)
        defer { ChatMediaTemporaryFiles.remove(url) }

        let sentContentType = LockIsolated<String?>(nil)
        let gif = KlipyGIF(id: "1", title: "", previewURL: "p", sendURL: "s", width: 2, height: 1, blurPreview: nil)
        let sent = ZMMessage(
            id: "sent",
            conversationId: "conversation",
            senderId: "me",
            content: "[GIF]",
            timestamp: Date(timeIntervalSince1970: 1),
            isFromMe: true
        )

        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.klipyGIF.download = { _ in url }
            $0.zappMessaging.sendMedia = { _, _, contentType, _, _ in
                sentContentType.withValue { $0 = contentType }
                return sent
            }
        }
        store.exhaustivity = .off

        await store.send(.gifButtonTapped)
        #expect(store.state.gifPicker != nil)

        await store.send(.gifPicker(.presented(.delegate(.selected(gif)))))

        #expect(store.state.gifPicker == nil)
        #expect(store.state.isSendingMedia)

        await store.receive(\.gifDownloaded)
        await store.receive(\.mediaSendSucceeded)

        #expect(sentContentType.value == "image/gif")
        #expect(!store.state.isSendingMedia)
        #expect(!store.state.sendDidFail)
        #expect(store.state.messages == [sent])
    }

    @MainActor @Test func aFailedGifDownloadClearsTheSendingStateAndReportsFailure() async {
        let gif = KlipyGIF(id: "1", title: "", previewURL: "p", sendURL: "s", width: 2, height: 1, blurPreview: nil)
        var state = ChatRoom.State(conversationId: "conversation")
        state.gifPicker = ChatGIFPicker.State()

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.klipyGIF.download = { _ in throw DownloadFailure() }
        }
        store.exhaustivity = .off

        await store.send(.gifPicker(.presented(.delegate(.selected(gif)))))
        await store.receive(\.mediaSendFailed)

        #expect(!store.state.isSendingMedia)
        #expect(store.state.sendDidFail)
    }

    /// The composer only offers a GIF button when a Klipy key is configured; without one the
    /// sheet would open onto a search that can never answer.
    @MainActor @Test func theGifButtonStaysHiddenWithoutAConfiguredKey() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) {
            ChatRoom()
        } withDependencies: {
            $0.klipyGIF.isConfigured = { false }
            $0.mainQueue = .immediate
            $0.zappMessaging.setActiveConversation = { _ in }
            $0.zappMessaging.markRead = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)

        #expect(!store.state.isGIFSearchAvailable)

        await store.send(.onDisappear)
    }
}
