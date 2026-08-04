//
//  ChatLinkPreviewTests.swift
//  zodlTests
//

import Testing
@testable import zodl_internal

@Suite("Chat link preview")
struct ChatLinkPreviewTests {
    @Test func parsesOpenGraphMetadataRegardlessOfAttributeOrder() throws {
        let html = """
        <html><head>
          <meta content="Zapp &amp; friends" property="og:title">
          <meta name='description' content='Private peer-to-peer messaging'>
          <meta content="Zapp" property="og:site_name">
          <meta property="og:image" content="/social/card.png">
        </head></html>
        """

        let preview = try #require(ChatLinkPreviewParser.parse(requestedURL: "https://zapp.example/story", html: html))

        #expect(preview.title == "Zapp & friends")
        #expect(preview.description == "Private peer-to-peer messaging")
        #expect(preview.siteName == "Zapp")
        #expect(preview.imageURL == "https://zapp.example/social/card.png")
    }

    @Test func fallsBackToTitleTagAndHost() throws {
        let preview = try #require(
            ChatLinkPreviewParser.parse(requestedURL: "https://www.example.com/a", html: "<title> Example page </title>")
        )

        #expect(preview.title == "Example page")
        #expect(preview.siteName == "example.com")
    }

    @Test func detectsLinksWithoutSwallowingSentencePunctuation() {
        let text = "See https://example.com/page, then http://example.org/test."
        let links = ChatLinkPreviewParser.detectWebURLs(in: text)

        #expect(links.map(\.url) == ["https://example.com/page", "http://example.org/test"])
        #expect(ChatLinkPreviewParser.firstWebURL(in: "See https://example.com/page.") == "https://example.com/page")
    }

    /// The bubble underlines exactly this span, so a range that includes the trailing comma
    /// would make punctuation part of the tap target.
    @Test func reportsTheRangeOfEachLinkWithoutItsTrailingPunctuation() throws {
        let text = "See https://example.com/page, then stop."
        let link = try #require(ChatLinkPreviewParser.detectWebURLs(in: text).first)

        #expect(String(text[link.range]) == "https://example.com/page")
    }

    /// The screening that keeps a peer-controlled URL from pointing the device at the local
    /// network. Plaintext, credentials, odd ports, and private hosts must all refuse to resolve.
    @Test func onlyPreviewsSafePublicHTTPSURLs() {
        #expect(ChatLinkPreviewParser.safePreviewURL("http://example.com") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://localhost/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://127.0.0.1/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://[::1]/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://192.168.1.2/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://10.0.0.5/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://169.254.169.254/latest/meta-data") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://172.16.4.4/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://user:password@example.com/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://example.com:8443/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://router.local/page") == nil)
        #expect(ChatLinkPreviewParser.safePreviewURL("https://example.com/page") == "https://example.com/page")
        #expect(ChatLinkPreviewParser.safePreviewURL("https://example.com:443/page") == "https://example.com:443/page")
    }

    @Test func rejectsUnsafeMetadataImages() throws {
        let html = """
        <meta property="og:title" content="Safe page">
        <meta property="og:image" content="https://127.0.0.1/private.png">
        """

        let preview = try #require(ChatLinkPreviewParser.parse(requestedURL: "https://example.com/page", html: html))

        #expect(preview.imageURL == nil)
    }

    @Test func returnsNothingWhenThePageCarriesNoMetadata() {
        #expect(ChatLinkPreviewParser.parse(requestedURL: "https://example.com", html: "<html><body>hi</body></html>") == nil)
    }

    @Test func clampsOverlongMetadata() throws {
        let long = String(repeating: "a", count: 900)
        let html = "<meta property=\"og:title\" content=\"\(long)\"><meta property=\"og:description\" content=\"\(long)\">"

        let preview = try #require(ChatLinkPreviewParser.parse(requestedURL: "https://example.com", html: html))

        #expect(preview.title?.count == ChatLinkPreviewParser.maxTitleLength)
        #expect(preview.description?.count == ChatLinkPreviewParser.maxDescriptionLength)
    }
}
