// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

struct DailyFiatPrice: Codable, Equatable, Sendable {
    let date: Date
    let fiatPerZec: Decimal
}

struct DailyPriceSeries: Equatable, Sendable {
    let fiatCurrency: CurrencyISO4217
    let points: [DailyFiatPrice]
    let availableFrom: Date
    let availableTo: Date
    let dataAsOf: Date
}

struct PriceDateRange: Codable, Equatable, Sendable {
    let from: Date
    let to: Date

    init(from: Date, to: Date) {
        precondition(from <= to && HistoricalPriceDate.isDayBoundary(from) && HistoricalPriceDate.isDayBoundary(to))
        self.from = from
        self.to = to
    }
}

enum PricingFailure: Error, Equatable, Sendable {
    case seriesUnavailable
    case invalidResponse(String)
    case http(Int)
    case network
}

enum HistoricalPriceState: Equatable, Sendable {
    case data(DailyPriceSeries, isStale: Bool)
    case loading
    case unavailable(PricingFailure? = nil)
}

enum HistoricalPriceDate {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()

    static func startOfDay(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    static func addingDays(_ days: Int, to date: Date) -> Date {
        guard let result = utcCalendar.date(byAdding: .day, value: days, to: date) else {
            preconditionFailure("Unable to calculate a historical price date")
        }
        return result
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utcCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utcCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), dayString(date) == value else { return nil }
        return date
    }

    static func instantString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = utcCalendar.timeZone
        return formatter.string(from: date)
    }

    static func parseInstant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func isDayBoundary(_ date: Date) -> Bool {
        date == startOfDay(date)
    }
}
