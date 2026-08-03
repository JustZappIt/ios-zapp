//
//  ChatLinkPreviewLiveKey.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

extension ChatLinkPreviewClient: DependencyKey {
    static let liveValue = ChatLinkPreviewClient(
        load: { await ChatLinkPreviewLoader.shared.load($0) }
    )
}

extension ChatLinkPreviewClient: TestDependencyKey {
    static let testValue = ChatLinkPreviewClient(
        load: { _ in nil }
    )
}

/// Fetches Open Graph metadata for a link.
///
/// A preview fetch is an outbound HTTPS request to a host named in message text, so the
/// screening in `ChatLinkPreviewParser.safePreviewURL` is applied twice: once to the requested
/// URL, and again to the URL the response actually came from, which is where redirects land.
private actor ChatLinkPreviewLoader {
    static let shared = ChatLinkPreviewLoader()

    private enum Constants {
        static let maxResponseBytes = 256 * 1024
        static let maxImageBytes = 2 * 1024 * 1024
        static let cacheSize = 128
        static let timeout: TimeInterval = 10
        static let userAgent = "Zapp/iOS LinkPreview"
        static let supportedContentTypes: Set<String> = ["text/html", "application/xhtml+xml"]
    }

    /// A miss is cached as `nil` too: a page without metadata must not be refetched on
    /// every redraw of the row that mentions it.
    private var cache: [String: ChatLinkPreview?] = [:]
    private var order: [String] = []

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Constants.timeout

        return URLSession(configuration: configuration)
    }()

    func load(_ rawURL: String) async -> ChatLinkPreview? {
        guard let url = ChatLinkPreviewParser.safePreviewURL(rawURL) else { return nil }

        if let cached = cache[url] { return cached }

        let preview = await fetch(url)
        store(preview, for: url)

        return preview
    }

    private func store(_ preview: ChatLinkPreview?, for url: String) {
        if cache[url] == nil {
            order.append(url)
        }

        cache[url] = preview

        while order.count > Constants.cacheSize {
            cache.removeValue(forKey: order.removeFirst())
        }
    }

    private func fetch(_ url: String) async -> ChatLinkPreview? {
        guard let requestURL = URL(string: url) else { return nil }

        do {
            var request = URLRequest(url: requestURL)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")

            let (bytes, response) = try await session.bytes(for: request)

            guard
                let httpResponse = response as? HTTPURLResponse,
                let finalURL = httpResponse.url.flatMap({ ChatLinkPreviewParser.safePreviewURL($0.absoluteString) }),
                isPreviewableHTML(httpResponse),
                declaredLength(httpResponse) ?? 0 <= Constants.maxResponseBytes,
                let data = try await read(bytes, limit: Constants.maxResponseBytes),
                var preview = ChatLinkPreviewParser.parse(
                    requestedURL: finalURL,
                    html: String(decoding: data, as: UTF8.self)
                )
            else {
                return nil
            }

            if let imageURL = preview.imageURL {
                preview.imageData = try? await loadImage(imageURL)
            }

            return preview
        } catch {
            return nil
        }
    }

    private func loadImage(_ url: String) async throws -> Data? {
        guard let safeURL = ChatLinkPreviewParser.safePreviewURL(url), let imageURL = URL(string: safeURL) else {
            return nil
        }

        var request = URLRequest(url: imageURL)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.url.flatMap({ ChatLinkPreviewParser.safePreviewURL($0.absoluteString) }) != nil,
            contentType(httpResponse)?.hasPrefix("image/") == true,
            declaredLength(httpResponse) ?? 0 <= Constants.maxImageBytes
        else {
            return nil
        }

        return try await read(bytes, limit: Constants.maxImageBytes)
    }

    /// Streams rather than trusting `Content-Length`: a server can under-declare it, and the
    /// point of the cap is to bound what an untrusted host can make the device hold.
    private func read(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data? {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))

        for try await byte in bytes {
            data.append(byte)

            if data.count > limit { return nil }
        }

        return data
    }

    private func isPreviewableHTML(_ response: HTTPURLResponse) -> Bool {
        guard let contentType = contentType(response) else { return true }

        return Constants.supportedContentTypes.contains(contentType)
    }

    private func contentType(_ response: HTTPURLResponse) -> String? {
        (response.value(forHTTPHeaderField: "Content-Type"))?
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private func declaredLength(_ response: HTTPURLResponse) -> Int? {
        response.expectedContentLength >= 0 ? Int(response.expectedContentLength) : nil
    }
}
