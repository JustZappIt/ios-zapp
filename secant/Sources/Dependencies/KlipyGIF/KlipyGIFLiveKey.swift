//
//  KlipyGIFLiveKey.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

extension KlipyGIFClient: DependencyKey {
    static let liveValue = KlipyGIFClient(
        isConfigured: { KlipyGIFCatalog.apiKey != nil },
        trending: { try await KlipyGIFService.shared.trending(page: $0) },
        search: { try await KlipyGIFService.shared.search($0, page: $1) },
        preview: { try await KlipyGIFService.shared.preview($0) },
        download: { try await KlipyGIFService.shared.download($0) }
    )
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
        static let previewCacheBytes = 24 * 1024 * 1024
    }

    private let customerId = UUID().uuidString

    /// `NSCache` rather than a hand-rolled LRU so a grid of previews is evicted under memory
    /// pressure instead of being held for the lifetime of the process.
    private let previewCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = Constants.previewCacheBytes

        return cache
    }()

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

    func trending(page: Int) async throws -> KlipyGIFPage {
        try await catalog(path: "trending", query: nil, page: page)
    }

    func search(_ query: String, page: Int) async throws -> KlipyGIFPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return try await trending(page: page) }

        return try await catalog(path: "search", query: trimmed, page: page)
    }

    func preview(_ gif: KlipyGIF) async throws -> Data {
        if let cached = previewCache.object(forKey: gif.previewURL as NSString) { return cached as Data }
        if let existing = inFlightPreviews[gif.previewURL] { return try await existing.value }

        let task = Task {
            try await body(
                for: try imageRequest(gif.previewURL),
                limit: KlipyGIFCatalog.previewByteLimit,
                pathExtension: "gif"
            )
        }
        inFlightPreviews[gif.previewURL] = task

        defer { inFlightPreviews[gif.previewURL] = nil }

        let data = try await task.value
        previewCache.setObject(data as NSData, forKey: gif.previewURL as NSString, cost: data.count)

        return data
    }

    func download(_ gif: KlipyGIF) async throws -> URL {
        let fileURL = try await fetch(
            try imageRequest(gif.sendURL),
            limit: ChatMediaEncoder.maxGIFBytes,
            pathExtension: "gif"
        )

        guard ChatMediaImage.isGIF(at: fileURL) else {
            ChatMediaTemporaryFiles.remove(fileURL)
            throw KlipyGIFError.badResponse
        }

        return fileURL
    }

    private func catalog(path: String, query: String?, page: Int) async throws -> KlipyGIFPage {
        let url = try KlipyGIFCatalog.endpoint(
            path: path,
            query: query,
            page: page,
            customerId: customerId,
            apiKey: KlipyGIFCatalog.apiKey
        )

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try KlipyGIFCatalog.parse(
            try await body(for: request, limit: Constants.maxResponseBytes, pathExtension: "json")
        )
    }

    /// Klipy names its own CDN, but it is still a third party naming a host — so a rendition goes
    /// through the same screening a link preview gets.
    private func imageRequest(_ url: String) throws -> URLRequest {
        guard
            let safeURL = ChatLinkPreviewParser.safePreviewURL(url),
            let requestURL = URL(string: safeURL)
        else {
            throw KlipyGIFError.badResponse
        }

        var request = URLRequest(url: requestURL)
        request.setValue("image/gif", forHTTPHeaderField: "Accept")

        return request
    }

    private func body(for request: URLRequest, limit: Int, pathExtension: String) async throws -> Data {
        let fileURL = try await fetch(request, limit: limit, pathExtension: pathExtension)

        defer { ChatMediaTemporaryFiles.remove(fileURL) }

        return try Data(contentsOf: fileURL)
    }

    /// Streamed to disk rather than accumulated in memory: `URLSession`'s in-memory conveniences
    /// buffer the whole body, and policing that through `AsyncBytes` costs one `await` per byte —
    /// seconds of CPU on a multi-megabyte GIF. The size is checked once the body has landed, so a
    /// host that under-declares its length spends temporary disk rather than memory.
    private func fetch(_ request: URLRequest, limit: Int, pathExtension: String) async throws -> URL {
        let (downloadedURL, response) = try await session.download(for: request)
        let fileURL = ChatMediaTemporaryFiles.makeURL(pathExtension: pathExtension)

        do {
            try FileManager.default.moveItem(at: downloadedURL, to: fileURL)
        } catch {
            ChatMediaTemporaryFiles.remove(downloadedURL)
            throw KlipyGIFError.badResponse
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let byteCount = ChatMediaImage.fileByteCount(at: fileURL)
        else {
            ChatMediaTemporaryFiles.remove(fileURL)
            throw KlipyGIFError.badResponse
        }

        guard byteCount <= limit else {
            ChatMediaTemporaryFiles.remove(fileURL)
            throw KlipyGIFError.tooLarge
        }

        return fileURL
    }
}
