//
//  ChatLocation.swift
//  Zapp
//
//  The `application/location` body. ON THE WIRE, mirrored from Android:
//
//  * written by `ChatRoomVM.sendLocationMessage` — an `org.json` object with `latitude`,
//    `longitude`, `accuracy` (all doubles) in that insertion order
//  * read back by `bubbles/LocationBubble.kt` — `optDouble("latitude")` / `optDouble("longitude")`
//
//  Additive changes only, and never a field Android does not write.
//

import Foundation

struct ChatLocation: Equatable {
    let latitude: Double
    let longitude: Double
    /// Android writes it but never reads it back; kept so a round trip is lossless.
    let accuracy: Double?

    /// A malformed or legacy body is `nil`, so the row degrades to the plain-text bubble.
    ///
    /// Deliberately stricter than Android, whose `optDouble` turns a missing coordinate into
    /// `NaN` and renders "NaN, NaN" with a maps link to nowhere.
    static func parse(_ content: String) -> ChatLocation? {
        let object = ChatMessageJSON.object(content)

        guard
            let latitude = double(in: object, "latitude"),
            let longitude = double(in: object, "longitude"),
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }

        return ChatLocation(
            latitude: latitude,
            longitude: longitude,
            accuracy: double(in: object, "accuracy")
        )
    }

    /// The one builder. Each value goes through its shortest round-trip decimal form, so the body
    /// matches what `org.json` prints for the same double: `37.7749`, and `20` rather than `20.0`.
    ///
    /// `nil` for a coordinate that is not a real position. `JSONSerialization` raises an
    /// uncatchable exception on NaN or infinity, so nothing non-finite may reach the encoder.
    static func json(latitude: Double, longitude: Double, accuracy: Double) -> String? {
        guard
            latitude.isFinite, longitude.isFinite, accuracy.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
            let latitudeValue = Decimal(string: "\(latitude)", locale: posix),
            let longitudeValue = Decimal(string: "\(longitude)", locale: posix),
            let accuracyValue = Decimal(string: "\(max(accuracy, 0))", locale: posix)
        else {
            return nil
        }

        return ChatMessageJSON.encode([
            ("latitude", latitudeValue),
            ("longitude", longitudeValue),
            ("accuracy", accuracyValue)
        ])
    }

    /// `String.format(Locale.US, "%.6f, %.6f", lat, lng)`, as Android's bubble prints it.
    var coordinateText: String {
        "\(Self.coordinate(latitude)), \(Self.coordinate(longitude))"
    }

    /// Apple Maps with a pin at the shared point. Android hands a `geo:` URI to whatever maps app
    /// is installed; Apple Maps is the iOS equivalent and opens in the app when it is present.
    var mapsURL: URL? {
        let point = "\(Self.coordinate(latitude)),\(Self.coordinate(longitude))"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: point),
            URLQueryItem(name: "q", value: point)
        ]

        return components.url
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", locale: posix, value)
    }

    /// `optDouble` also coerces a numeric string, so a peer that quoted its coordinates still parses.
    private static func double(in object: [String: Any]?, _ key: String) -> Double? {
        let value: Double?

        switch object?[key] {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            value = number.doubleValue
        case let text as String:
            value = Double(text.trimmingCharacters(in: .whitespaces))
        default:
            value = nil
        }

        return value.flatMap { $0.isFinite ? $0 : nil }
    }
}
