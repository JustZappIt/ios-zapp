//
//  KlipyGIFLiveKey.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

extension KlipyGIFClient: DependencyKey {
    static let liveValue = KlipyGIFClient(
        isConfigured: { KlipyGIFCatalog.apiKey != nil },
        trending: { try await KlipyGIFService.shared.trending() },
        search: { try await KlipyGIFService.shared.search($0) },
        preview: { try await KlipyGIFService.shared.preview($0) },
        download: { try await KlipyGIFService.shared.download($0) }
    )
}

extension KlipyGIFClient: TestDependencyKey {
    static let testValue = KlipyGIFClient(
        isConfigured: { false },
        trending: { [] },
        search: { _ in [] },
        preview: { _ in Data() },
        download: { _ in throw KlipyGIFError.notConfigured }
    )
}

/// Request building and response parsing, kept off the actor so it is testable without network.
enum KlipyGIFCatalog {
    static let perPage = 30
    static let previewByteLimit = 2 * 1024 * 1024
    static let maxBlurPreviewChars = 8 * 1024

    /// `md` before `hd`: Klipy ships both at the same pixel size and `hd` differs only in encoding
    /// quality, so `hd` costs roughly double the bytes over a peer-to-peer transfer for a gain no
    /// one sees in a chat bubble.
    static let sendSizes = ["md", "hd", "sm", "xs"]
    /// `sm` is 220px against a ~320px cell; `xs` is 90px and visibly mushy.
    static let previewSizes = ["sm", "xs", "md", "hd"]

    static var apiKey: String? {
        PartnerKeys.klipyKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func endpoint(path: String, query: String?, customerId: String) throws -> URL {
        guard let apiKey else { throw KlipyGIFError.notConfigured }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.klipy.com"
        components.path = "/api/v1/\(apiKey)/gifs/\(path)"
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "customer_id", value: customerId),
            URLQueryItem(name: "content_filter", value: "high"),
            // Each item otherwise carries mp4/webm/webp/jpg renditions at four sizes, none of
            // which this picker can use.
            URLQueryItem(name: "format_filter", value: "gif")
        ]

        if let query {
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        }

        guard let url = components.url else { throw KlipyGIFError.badResponse }

        return url
    }

    static func parse(_ data: Data, maxSendBytes: Int = ChatMediaEncoder.maxGIFBytes) throws -> [KlipyGIF] {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let page = root["data"] as? [String: Any],
            let results = page["data"] as? [[String: Any]]
        else {
            throw KlipyGIFError.badResponse
        }

        return results.compactMap { result($0, maxSendBytes: maxSendBytes) }
    }

    /// An injected advertisement arrives in the same array as a `content` item carrying markup
    /// instead of a `file` — dropping those is what keeps the grid to actual GIFs.
    private static func result(_ raw: [String: Any], maxSendBytes: Int) -> KlipyGIF? {
        guard
            raw["content"] == nil,
            let identifier = identifier(raw),
            let sizes = raw["file"] as? [String: Any],
            let send = rendition(in: sizes, order: sendSizes, maxBytes: maxSendBytes),
            let preview = rendition(in: sizes, order: previewSizes, maxBytes: previewByteLimit)
        else {
            return nil
        }

        return KlipyGIF(
            id: identifier,
            title: (raw["title"] as? String) ?? "",
            previewURL: preview.url,
            sendURL: send.url,
            width: preview.width,
            height: preview.height,
            blurPreview: blurPreview(raw["blur_preview"] as? String)
        )
    }

    /// A `data:` URI rather than a link, so it is decoded rather than fetched. Bounded because it
    /// arrives from a third party and lands in memory for every cell on screen.
    static func blurPreview(_ raw: String?) -> Data? {
        guard
            let raw,
            raw.count <= maxBlurPreviewChars,
            let comma = raw.firstIndex(of: ","),
            raw[raw.startIndex..<comma].hasPrefix("data:image/")
        else {
            return nil
        }

        return Data(base64Encoded: String(raw[raw.index(after: comma)...]), options: [.ignoreUnknownCharacters])
    }

    private static func identifier(_ raw: [String: Any]) -> String? {
        if let slug = raw["slug"] as? String, !slug.isEmpty { return slug }

        return (raw["id"] as? NSNumber).map { $0.stringValue }
    }

    private struct Rendition {
        let url: String
        let width: Int
        let height: Int
    }

    private static func rendition(in sizes: [String: Any], order: [String], maxBytes: Int) -> Rendition? {
        for name in order {
            guard
                let formats = sizes[name] as? [String: Any],
                let gif = formats["gif"] as? [String: Any],
                let rawURL = gif["url"] as? String,
                let url = ChatLinkPreviewParser.safePreviewURL(rawURL)
            else {
                continue
            }

            // Klipy declares the byte count, so an oversized rendition is skipped before it is
            // ever requested rather than downloaded and thrown away.
            if let size = (gif["size"] as? NSNumber)?.intValue, size > maxBytes {
                continue
            }

            return Rendition(
                url: url,
                width: (gif["width"] as? NSNumber)?.intValue ?? 0,
                height: (gif["height"] as? NSNumber)?.intValue ?? 0
            )
        }

        return nil
    }
}

/// Klipy search for the composer's GIF picker.
///
/// The session is ephemeral and uncookied for the same reason the link-preview one is: this is an
/// outbound request to a third party from inside a private messenger. `customer_id` is required by
/// the API but is a fresh random value per launch, so it carries no identity across sessions and
/// nothing derived from the wallet.
private actor KlipyGIFService {
    static let shared = KlipyGIFService()

    private enum Constants {
        static let maxResponseBytes = 1024 * 1024
        static let timeout: TimeInterval = 15
        static let previewCacheSize = 120
    }

    private let customerId = UUID().uuidString

    private var previewCache: [String: Data] = [:]
    private var previewOrder: [String] = []
    private var inFlightPreviews: [String: Task<Data, Error>] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Constants.timeout
        configuration.httpMaximumConnectionsPerHost = 4

        return URLSession(configuration: configuration)
    }()

    func trending() async throws -> [KlipyGIF] {
        try await catalog(path: "trending", query: nil)
    }

    func search(_ query: String) async throws -> [KlipyGIF] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return try await trending() }

        return try await catalog(path: "search", query: trimmed)
    }

    func preview(_ gif: KlipyGIF) async throws -> Data {
        if let cached = previewCache[gif.previewURL] { return cached }
        if let existing = inFlightPreviews[gif.previewURL] { return try await existing.value }

        let task = Task { try await load(gif.previewURL, limit: KlipyGIFCatalog.previewByteLimit) }
        inFlightPreviews[gif.previewURL] = task

        defer { inFlightPreviews[gif.previewURL] = nil }

        let data = try await task.value
        store(data, for: gif.previewURL)

        return data
    }

    func download(_ gif: KlipyGIF) async throws -> URL {
        let data = try await load(gif.sendURL, limit: ChatMediaEncoder.maxGIFBytes)

        guard ChatMediaImage.isGIF(data) else { throw KlipyGIFError.badResponse }

        let url = ChatMediaTemporaryFiles.makeURL(pathExtension: "gif")
        try data.write(to: url, options: .atomic)

        return url
    }

    private func catalog(path: String, query: String?) async throws -> [KlipyGIF] {
        let url = try KlipyGIFCatalog.endpoint(path: path, query: query, customerId: customerId)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw KlipyGIFError.badResponse
        }

        return try KlipyGIFCatalog.parse(try await read(bytes, limit: Constants.maxResponseBytes))
    }

    private func load(_ url: String, limit: Int) async throws -> Data {
        guard
            let safeURL = ChatLinkPreviewParser.safePreviewURL(url),
            let requestURL = URL(string: safeURL)
        else {
            throw KlipyGIFError.badResponse
        }

        var request = URLRequest(url: requestURL)
        request.setValue("image/gif", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            httpResponse.expectedContentLength <= Int64(limit)
        else {
            throw KlipyGIFError.badResponse
        }

        return try await read(bytes, limit: limit)
    }

    /// Streamed rather than trusting `Content-Length`, which a host can under-declare.
    private func read(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))

        for try await byte in bytes {
            data.append(byte)

            if data.count > limit { throw KlipyGIFError.tooLarge }
        }

        return data
    }

    private func store(_ data: Data, for url: String) {
        if previewCache[url] == nil {
            previewOrder.append(url)
        }

        previewCache[url] = data

        while previewOrder.count > Constants.previewCacheSize {
            previewCache.removeValue(forKey: previewOrder.removeFirst())
        }
    }
}
