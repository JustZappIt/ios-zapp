// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension HistoricalPriceClient: DependencyKey {
    static let liveValue: HistoricalPriceClient = {
        let cache = HistoricalPriceCacheProvider()
        let dataSource = PricingEngineDataSource { request in
            @Dependency(\.sdkSynchronizer)
            var sdkSynchronizer
            @Shared(.inMemory(.swapAPIAccess))
            var swapAPIAccess: WalletStorage.SwapAPIAccess = .direct

            if swapAPIAccess == .direct {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                return (data, response)
            }
            return try await sdkSynchronizer.httpRequestOverTor(request)
        }
        let repository = HistoricalPriceRepository(dataSource: dataSource, cacheProvider: cache)

        return HistoricalPriceClient(
            states: { range, currency in
                AsyncStream { continuation in
                    let task = Task {
                        await repository.observe(range: range, currency: currency, continuation: continuation)
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }()
}

private struct PricingEngineDataSource: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private enum Constants {
        static let endpoint = "https://zapp-pricing-engine.majorworker.workers.dev/v1/prices"
        static let maximumPages = 20
        static let retryCount = 1
        static let retryBaseNanoseconds: UInt64 = 500_000_000
        static let retryJitterNanoseconds: UInt64 = 500_000_000
    }

    let transport: Transport

    func prices(range: PriceDateRange, currency: CurrencyISO4217) async -> Result<DailyPriceSeries, PricingFailure> {
        var requestFrom = range.from
        var expectedMetadata: HistoricalPricePage.Metadata?
        var points: [Date: DailyFiatPrice] = [:]

        for _ in 0..<Constants.maximumPages {
            let pageRange = PriceDateRange(from: requestFrom, to: range.to)
            let pageResponse: (Data, HTTPURLResponse)
            do {
                pageResponse = try await response(for: request(pageRange, currency: currency))
            } catch is CancellationError {
                return .failure(.network)
            } catch {
                return .failure(.network)
            }

            guard (200..<300).contains(pageResponse.1.statusCode) else {
                return .failure(parseHistoricalPriceError(status: pageResponse.1.statusCode, data: pageResponse.0))
            }

            let page: HistoricalPricePage
            switch parseHistoricalPricePage(data: pageResponse.0, requestedRange: pageRange, requestedFiat: currency) {
            case .success(let parsed):
                page = parsed
            case .failure(let failure):
                return .failure(failure)
            }

            if let expectedMetadata, expectedMetadata != page.metadata {
                return .failure(.invalidResponse("availability metadata changed between pages"))
            }
            expectedMetadata = page.metadata
            page.points.forEach { points[$0.date] = $0 }

            if page.complete {
                return .success(
                    DailyPriceSeries(
                        fiatCurrency: currency,
                        points: points.values.sorted { $0.date < $1.date },
                        availableFrom: page.metadata.availableFrom,
                        availableTo: page.metadata.availableTo,
                        dataAsOf: page.metadata.dataAsOf
                    )
                )
            }

            guard let cursor = page.nextCursor else {
                return .failure(.invalidResponse("incomplete page has no nextCursor"))
            }
            guard let lastDate = page.points.last?.date else {
                return .failure(.invalidResponse("incomplete page has no points"))
            }
            guard cursor > lastDate else {
                return .failure(.invalidResponse("nextCursor did not advance"))
            }
            let nextFrom = HistoricalPriceDate.startOfDay(cursor)
            guard nextFrom > requestFrom, nextFrom <= range.to else {
                return .failure(.invalidResponse("nextCursor is repeated, regressing, or out of range"))
            }
            requestFrom = nextFrom
        }

        return .failure(.invalidResponse("price series exceeded the page limit"))
    }

    private func request(_ range: PriceDateRange, currency: CurrencyISO4217) -> URLRequest {
        var components = URLComponents(string: Constants.endpoint)
        // Keep this order stable because it is part of the Worker's CDN cache key.
        components?.queryItems = [
            URLQueryItem(name: "asset", value: "ZEC"),
            URLQueryItem(name: "fiat", value: currency.code),
            URLQueryItem(name: "resolution", value: "1d"),
            URLQueryItem(name: "from", value: HistoricalPriceDate.dayString(range.from)),
            URLQueryItem(name: "to", value: HistoricalPriceDate.dayString(range.to)),
            URLQueryItem(name: "limit", value: "1000")
        ]
        guard let url = components?.url else {
            preconditionFailure("Invalid historical pricing endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do {
                let response = try await transport(request)
                if response.1.statusCode < 500 || attempt >= Constants.retryCount {
                    return response
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < Constants.retryCount else { throw error }
            }

            let jitter = UInt64.random(in: 0...Constants.retryJitterNanoseconds)
            try await Task.sleep(nanoseconds: Constants.retryBaseNanoseconds + jitter)
            attempt += 1
        }
    }
}

struct HistoricalPricePage: Equatable {
    struct Metadata: Equatable {
        let availableFrom: Date
        let availableTo: Date
        let dataAsOf: Date
    }

    let points: [DailyFiatPrice]
    let metadata: Metadata
    let complete: Bool
    let nextCursor: Date?
}

func parseHistoricalPricePage(
    data: Data,
    requestedRange: PriceDateRange,
    requestedFiat: CurrencyISO4217
) -> Result<HistoricalPricePage, PricingFailure> {
    let response: PriceSeriesResponse
    do {
        response = try JSONDecoder().decode(PriceSeriesResponse.self, from: data)
    } catch {
        return .failure(.invalidResponse("malformed success response"))
    }

    guard response.asset == "ZEC", response.fiat == requestedFiat.code, response.resolution == "1d" else {
        return .failure(.invalidResponse("response series does not match ZEC/\(requestedFiat.code)/1d"))
    }
    guard let from = response.from.flatMap(HistoricalPriceDate.parseInstant),
        let to = response.to.flatMap(HistoricalPriceDate.parseInstant) else {
        return .failure(.invalidResponse("invalid response bounds"))
    }
    guard from == requestedRange.from, to == requestedRange.to else {
        return .failure(.invalidResponse("response bounds contradict the request"))
    }
    guard let availableFrom = response.availableFrom.flatMap(HistoricalPriceDate.parseInstant),
        let availableTo = response.availableTo.flatMap(HistoricalPriceDate.parseInstant),
        let dataAsOf = response.dataAsOf.flatMap(HistoricalPriceDate.parseInstant) else {
        return .failure(.invalidResponse("invalid availability metadata"))
    }
    guard HistoricalPriceDate.isDayBoundary(availableFrom), HistoricalPriceDate.isDayBoundary(availableTo) else {
        return .failure(.invalidResponse("daily availability is not aligned to UTC dates"))
    }
    guard availableFrom <= availableTo, dataAsOf == availableTo else {
        return .failure(.invalidResponse("availability metadata is contradictory"))
    }
    // Availability sitting entirely outside the range we asked about describes a different series.
    // It also has teeth: the ALL period builds its window from `availableFrom`, so a value past the
    // last completed day would invert that range.
    guard availableFrom <= requestedRange.to, availableTo >= requestedRange.from else {
        return .failure(.invalidResponse("availability metadata does not overlap the request"))
    }
    guard let complete = response.complete else {
        return .failure(.invalidResponse("missing complete"))
    }
    guard let pointResponses = response.points else {
        return .failure(.invalidResponse("missing points"))
    }

    let nextCursor: Date?
    if let value = response.nextCursor {
        guard let parsed = HistoricalPriceDate.parseInstant(value) else {
            return .failure(.invalidResponse("invalid nextCursor"))
        }
        nextCursor = parsed
    } else {
        nextCursor = nil
    }
    guard !complete || nextCursor == nil else {
        return .failure(.invalidResponse("complete response contains nextCursor"))
    }

    var previousTimestamp: Date?
    var points: [DailyFiatPrice] = []
    for point in pointResponses {
        guard let timestamp = point.timestamp.flatMap(HistoricalPriceDate.parseInstant) else {
            return .failure(.invalidResponse("invalid point timestamp"))
        }
        guard HistoricalPriceDate.isDayBoundary(timestamp),
            timestamp >= from, timestamp <= to,
            timestamp >= availableFrom, timestamp <= availableTo else {
            return .failure(.invalidResponse("point timestamp contradicts metadata"))
        }
        if let previousTimestamp, timestamp <= previousTimestamp {
            return .failure(.invalidResponse("point timestamps are unordered or duplicated"))
        }
        previousTimestamp = timestamp

        guard let price = point.price, let priceUsd = point.priceUsd, let unitsPerUsd = point.unitsPerUsd,
            price.isFinite, priceUsd.isFinite, unitsPerUsd.isFinite,
            price > 0, priceUsd > 0, unitsPerUsd > 0 else {
            return .failure(.invalidResponse("point contains a non-positive or non-finite price"))
        }
        if requestedFiat == .usd, unitsPerUsd != 1 {
            return .failure(.invalidResponse("USD point has a non-unit conversion rate"))
        }
        let expectedFiatPrice = priceUsd * unitsPerUsd
        let tolerance = max(abs(expectedFiatPrice), 1) * 1e-12
        guard abs(price - expectedFiatPrice) <= tolerance else {
            return .failure(.invalidResponse("point price contradicts its USD price and fiat conversion rate"))
        }
        points.append(DailyFiatPrice(date: timestamp, fiatPerZec: Decimal(price)))
    }

    return .success(
        HistoricalPricePage(
            points: points,
            metadata: .init(availableFrom: availableFrom, availableTo: availableTo, dataAsOf: dataAsOf),
            complete: complete,
            nextCursor: nextCursor
        )
    )
}

func parseHistoricalPriceError(status: Int, data: Data) -> PricingFailure {
    guard let envelope = try? JSONDecoder().decode(PricingErrorEnvelope.self, from: data) else {
        return .invalidResponse("malformed error response")
    }
    guard let code = envelope.error?.code else {
        return .invalidResponse("missing error code")
    }
    if code == "SERIES_UNAVAILABLE" {
        return .seriesUnavailable
    }
    if ["INVALID_QUERY", "METHOD_NOT_ALLOWED", "ROUTE_NOT_FOUND", "INTERNAL_ERROR"].contains(code) {
        return .http(status)
    }
    return .invalidResponse("unknown error code: \(code)")
}

private struct PriceSeriesResponse: Decodable {
    let asset: String?
    let fiat: String?
    let resolution: String?
    let from: String?
    let to: String?
    let availableFrom: String?
    let availableTo: String?
    let dataAsOf: String?
    let complete: Bool?
    let nextCursor: String?
    let points: [PricePointResponse]?
}

private struct PricePointResponse: Decodable {
    let timestamp: String?
    let price: Double?
    let priceUsd: Double?
    let unitsPerUsd: Double?
}

private struct PricingErrorEnvelope: Decodable {
    struct PricingError: Decodable {
        let code: String?
    }

    let error: PricingError?
}

private struct HistoricalPriceCacheProvider: Sendable {
    private static let schemaVersion = 2

    func load(_ currency: CurrencyISO4217) -> HistoricalPriceCache? {
        deleteVersionedFiles(currency)
        let url = fileURL(currency)
        guard let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(HistoricalPriceCache.self, from: data),
            cache.schemaVersion == Self.schemaVersion,
            cache.fiatCurrencyCode == currency.code else {
            return nil
        }
        return cache
    }

    func store(_ cache: HistoricalPriceCache, currency: CurrencyISO4217) throws {
        precondition(cache.fiatCurrencyCode == currency.code)
        deleteVersionedFiles(currency)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: fileURL(currency), options: .atomic)
    }

    private func fileURL(_ currency: CurrencyISO4217) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("historical_zec_\(currency.code.lowercased())_prices.json")
    }

    private func deleteVersionedFiles(_ currency: CurrencyISO4217) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let prefix = "historical_zec_\(currency.code.lowercased())_prices_v"
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.filter { $0.lastPathComponent.hasPrefix(prefix) }.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

private struct HistoricalPriceCache: Codable {
    struct CachedPrice: Codable {
        let date: String
        let fiatPerZec: String
    }

    struct CachedRange: Codable {
        let from: String
        let to: String
    }

    let schemaVersion: Int
    let fiatCurrencyCode: String
    let availableFrom: String?
    let availableTo: String?
    let dataAsOf: String?
    let points: [CachedPrice]
    let completedRanges: [CachedRange]
    let lastCompletedRequestDate: String?
    let unavailableCheckedAt: String?
    let refreshNotBefore: String?
}

private actor HistoricalPriceRepository {
    private enum Constants {
        static let failureCooldown: TimeInterval = 5 * 60
        static let incompleteCooldown: TimeInterval = 60 * 60
    }

    private enum RefreshResult: Sendable {
        case updated(Snapshot)
        case failed(PricingFailure?)
    }

    private struct RefreshTask {
        let id: UUID
        let task: Task<RefreshResult, Never>
    }

    fileprivate struct Snapshot: Sendable {
        let currency: CurrencyISO4217
        var points: [Date: DailyFiatPrice]
        var completedRanges: [PriceDateRange]
        var availableFrom: Date?
        var availableTo: Date?
        var dataAsOf: Date?
        var unavailableCheckedAt: Date?
        var refreshNotBefore: Date?

        func covers(_ range: PriceDateRange) -> Bool {
            completedRanges.contains { $0.from <= range.from && $0.to >= range.to }
        }

        func series(for range: PriceDateRange) -> DailyPriceSeries? {
            guard let availableFrom, let availableTo, let dataAsOf else { return nil }
            return DailyPriceSeries(
                fiatCurrency: currency,
                points: points.values.filter { $0.date >= range.from && $0.date <= range.to }.sorted { $0.date < $1.date },
                availableFrom: availableFrom,
                availableTo: availableTo,
                dataAsOf: dataAsOf
            )
        }

        func uncoveredRanges(_ range: PriceDateRange) -> [PriceDateRange] {
            var result: [PriceDateRange] = []
            var start: Date?
            var date = range.from
            while date <= range.to {
                let covered = completedRanges.contains { date >= $0.from && date <= $0.to }
                if !covered, start == nil { start = date }
                if covered, let missingStart = start {
                    result.append(.init(from: missingStart, to: HistoricalPriceDate.addingDays(-1, to: date)))
                    start = nil
                }
                date = HistoricalPriceDate.addingDays(1, to: date)
            }
            if let start { result.append(.init(from: start, to: range.to)) }
            return result
        }

        func unavailableIsFresh(_ now: Date) -> Bool {
            guard let unavailableCheckedAt else { return false }
            return HistoricalPriceDate.startOfDay(unavailableCheckedAt) == HistoricalPriceDate.startOfDay(now)
        }

        func refreshIsSuppressed(_ now: Date) -> Bool {
            refreshNotBefore.map { $0 > now } ?? false
        }
    }

    private let dataSource: PricingEngineDataSource
    private let cacheProvider: HistoricalPriceCacheProvider
    private var refreshTasks: [CurrencyISO4217: RefreshTask] = [:]
    private var snapshots: [CurrencyISO4217: Snapshot] = [:]

    init(dataSource: PricingEngineDataSource, cacheProvider: HistoricalPriceCacheProvider) {
        self.dataSource = dataSource
        self.cacheProvider = cacheProvider
    }

    func observe(
        range: PriceDateRange,
        currency: CurrencyISO4217,
        continuation: AsyncStream<HistoricalPriceState>.Continuation
    ) async {
        let initial = snapshot(currency)
        let cached = initial.series(for: range)
        if let cached { continuation.yield(.data(cached, isStale: !initial.covers(range))) }

        let now = Date()
        if initial.covers(range) {
            if cached == nil { continuation.yield(.unavailable()) }
            continuation.finish()
            return
        }
        if initial.unavailableIsFresh(now) {
            if cached == nil { continuation.yield(.unavailable(.seriesUnavailable)) }
            continuation.finish()
            return
        }
        if initial.refreshIsSuppressed(now) {
            if cached == nil { continuation.yield(.unavailable()) }
            continuation.finish()
            return
        }
        if cached == nil { continuation.yield(.loading) }

        switch await refreshSerialized(range: range, currency: currency) {
        case .updated(let updated):
            if let series = updated.series(for: range) {
                continuation.yield(.data(series, isStale: !updated.covers(range)))
            } else {
                continuation.yield(.unavailable())
            }
        case .failed(let failure):
            if cached == nil { continuation.yield(.unavailable(failure)) }
        }
        continuation.finish()
    }

    private func snapshot(_ currency: CurrencyISO4217) -> Snapshot {
        if let snapshot = snapshots[currency] { return snapshot }
        let loaded = Snapshot.from(cacheProvider.load(currency), currency: currency)
        snapshots[currency] = loaded
        return loaded
    }

    private func refreshSerialized(range: PriceDateRange, currency: CurrencyISO4217) async -> RefreshResult {
        guard !Task.isCancelled else { return .failed(nil) }
        if let existing = refreshTasks[currency] {
            _ = await existing.task.value
            if refreshTasks[currency]?.id == existing.id {
                refreshTasks[currency] = nil
            }
            guard !Task.isCancelled else { return .failed(nil) }
            return await refreshSerialized(range: range, currency: currency)
        }

        let latest = snapshot(currency)
        if latest.covers(range) { return .updated(latest) }
        if latest.unavailableIsFresh(Date()) { return .failed(.seriesUnavailable) }
        if latest.refreshIsSuppressed(Date()) { return .failed(nil) }

        let id = UUID()
        let task = Task { await refresh(range: range, currency: currency) }
        refreshTasks[currency] = RefreshTask(id: id, task: task)
        let result = await task.value
        if refreshTasks[currency]?.id == id {
            refreshTasks[currency] = nil
        }
        return result
    }

    private func refresh(range: PriceDateRange, currency: CurrencyISO4217) async -> RefreshResult {
        var working = snapshot(currency)
        for missingRange in working.uncoveredRanges(range) {
            let result = await dataSource.prices(range: missingRange, currency: currency)
            guard !Task.isCancelled else { return .failed(nil) }
            switch result {
            case .success(let series):
                guard series.fiatCurrency == currency else {
                    return persistFailure(.invalidResponse("series fiat currency changed"), snapshot: &working, currency: currency)
                }
                working.upsert(
                    series,
                    requestedRange: missingRange,
                    now: Date(),
                    incompleteCooldown: Constants.incompleteCooldown
                )
                persist(working, currency: currency)
            case .failure(let failure):
                return persistFailure(failure, snapshot: &working, currency: currency)
            }
        }
        if working.covers(range), working.refreshNotBefore != nil {
            working.refreshNotBefore = nil
            persist(working, currency: currency)
        }
        return .updated(working)
    }

    private func persistFailure(
        _ failure: PricingFailure,
        snapshot: inout Snapshot,
        currency: CurrencyISO4217
    ) -> RefreshResult {
        if failure == .seriesUnavailable {
            snapshot.unavailableCheckedAt = Date()
            snapshot.refreshNotBefore = nil
        } else {
            snapshot.refreshNotBefore = Date().addingTimeInterval(Constants.failureCooldown)
        }
        persist(snapshot, currency: currency)
        return .failed(failure)
    }

    private func persist(_ snapshot: Snapshot, currency: CurrencyISO4217) {
        snapshots[currency] = snapshot
        do {
            try cacheProvider.store(snapshot.cache, currency: currency)
        } catch {
            LoggerProxy.warn("Historical price cache write failed: \(error)")
        }
    }
}

private extension HistoricalPriceRepository.Snapshot {
    static func from(_ cache: HistoricalPriceCache?, currency: CurrencyISO4217) -> Self {
        guard let cache, cache.fiatCurrencyCode == currency.code else { return empty(currency) }

        var prices: [Date: DailyFiatPrice] = [:]
        for cached in cache.points {
            guard let date = HistoricalPriceDate.parseDay(cached.date),
                let price = Decimal(string: cached.fiatPerZec, locale: Locale(identifier: "en_US_POSIX")),
                price > 0 else { return empty(currency) }
            prices[date] = DailyFiatPrice(date: date, fiatPerZec: price)
        }
        let parsedRanges = cache.completedRanges.compactMap { range -> PriceDateRange? in
            guard let from = HistoricalPriceDate.parseDay(range.from), let to = HistoricalPriceDate.parseDay(range.to), from <= to else {
                return nil
            }
            return PriceDateRange(from: from, to: to)
        }
        guard parsedRanges.count == cache.completedRanges.count else { return empty(currency) }

        let availableFrom = cache.availableFrom.flatMap(HistoricalPriceDate.parseDay)
        let availableTo = cache.availableTo.flatMap(HistoricalPriceDate.parseDay)
        let dataAsOf = cache.dataAsOf.flatMap(HistoricalPriceDate.parseInstant)
        guard (cache.availableFrom == nil) == (availableFrom == nil),
            (cache.availableTo == nil) == (availableTo == nil),
            (cache.dataAsOf == nil) == (dataAsOf == nil),
            (availableFrom == nil) == (availableTo == nil),
            (availableTo == nil) == (dataAsOf == nil) else {
            return empty(currency)
        }

        let unavailableCheckedAt = cache.unavailableCheckedAt.flatMap(HistoricalPriceDate.parseInstant)
        let refreshNotBefore = cache.refreshNotBefore.flatMap(HistoricalPriceDate.parseInstant)
        guard (cache.unavailableCheckedAt == nil) == (unavailableCheckedAt == nil),
            (cache.refreshNotBefore == nil) == (refreshNotBefore == nil) else {
            return empty(currency)
        }

        let completedRanges: [PriceDateRange]
        if let availableFrom, let availableTo {
            guard availableFrom <= availableTo else { return empty(currency) }
            let availableRange = PriceDateRange(from: availableFrom, to: availableTo)
            let previouslyCompletedDates = prices.keys.filter { date in
                date >= availableRange.from && date <= availableRange.to && parsedRanges.contains { date >= $0.from && date <= $0.to }
            }
            completedRanges = mergeHistoricalPriceRanges(previouslyCompletedDates.map { .init(from: $0, to: $0) })
        } else {
            completedRanges = []
        }

        return Self(
            currency: currency,
            points: prices,
            completedRanges: completedRanges,
            availableFrom: availableFrom,
            availableTo: availableTo,
            dataAsOf: dataAsOf,
            unavailableCheckedAt: unavailableCheckedAt,
            refreshNotBefore: refreshNotBefore
        )
    }

    static func empty(_ currency: CurrencyISO4217) -> Self {
        Self(
            currency: currency,
            points: [:],
            completedRanges: [],
            availableFrom: nil,
            availableTo: nil,
            dataAsOf: nil,
            unavailableCheckedAt: nil,
            refreshNotBefore: nil
        )
    }

    mutating func upsert(
        _ series: DailyPriceSeries,
        requestedRange: PriceDateRange,
        now: Date,
        incompleteCooldown: TimeInterval
    ) {
        series.points.forEach { points[$0.date] = $0 }
        let completedFrom = max(requestedRange.from, series.availableFrom)
        let completedTo = min(requestedRange.to, series.availableTo)
        let fetchedRanges: [PriceDateRange]
        if completedFrom <= completedTo {
            // Pagination being complete does not guarantee every daily row exists. Recording only
            // returned dates keeps ingestion gaps eligible for backfill after the cooldown.
            fetchedRanges = series.points
                .map(\.date)
                .filter { $0 >= completedFrom && $0 <= completedTo }
                .map { PriceDateRange(from: $0, to: $0) }
        } else {
            fetchedRanges = []
        }
        completedRanges = mergeHistoricalPriceRanges(completedRanges + fetchedRanges)
        availableFrom = availableFrom.map { min($0, series.availableFrom) } ?? series.availableFrom
        availableTo = availableTo.map { max($0, series.availableTo) } ?? series.availableTo
        dataAsOf = dataAsOf.map { max($0, series.dataAsOf) } ?? series.dataAsOf
        unavailableCheckedAt = nil
        refreshNotBefore = covers(requestedRange) ? nil : now.addingTimeInterval(incompleteCooldown)
    }

    var cache: HistoricalPriceCache {
        HistoricalPriceCache(
            schemaVersion: 2,
            fiatCurrencyCode: currency.code,
            availableFrom: availableFrom.map(HistoricalPriceDate.dayString),
            availableTo: availableTo.map(HistoricalPriceDate.dayString),
            dataAsOf: dataAsOf.map(HistoricalPriceDate.instantString),
            points: points.values.sorted { $0.date < $1.date }.map {
                .init(date: HistoricalPriceDate.dayString($0.date), fiatPerZec: NSDecimalNumber(decimal: $0.fiatPerZec).stringValue)
            },
            completedRanges: completedRanges.map {
                .init(from: HistoricalPriceDate.dayString($0.from), to: HistoricalPriceDate.dayString($0.to))
            },
            lastCompletedRequestDate: completedRanges.map(\.to).max().map(HistoricalPriceDate.dayString),
            unavailableCheckedAt: unavailableCheckedAt.map(HistoricalPriceDate.instantString),
            refreshNotBefore: refreshNotBefore.map(HistoricalPriceDate.instantString)
        )
    }
}

private func mergeHistoricalPriceRanges(_ ranges: [PriceDateRange]) -> [PriceDateRange] {
    let sorted = ranges.sorted { $0.from < $1.from }
    guard var current = sorted.first else { return [] }
    var merged: [PriceDateRange] = []
    for range in sorted.dropFirst() {
        if range.from <= HistoricalPriceDate.addingDays(1, to: current.to) {
            current = PriceDateRange(from: current.from, to: max(current.to, range.to))
        } else {
            merged.append(current)
            current = range
        }
    }
    merged.append(current)
    return merged
}
