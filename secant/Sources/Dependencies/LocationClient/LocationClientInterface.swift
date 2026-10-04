//
//  LocationClientInterface.swift
//  Zapp
//
//  One-shot device location for the chat composer's "Location" attachment. Mirrors what
//  Android's `ChatRoomEffectsHandler.shareLocation` asks of Play Services: When-In-Use
//  permission, then a single high-accuracy fix. Nothing here tracks the user.
//

import ComposableArchitecture

extension DependencyValues {
    var location: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}

struct LocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Horizontal accuracy in metres.
    let accuracy: Double
}

enum LocationFailure: Error, Equatable {
    /// Permission was withdrawn while the fix was in flight.
    case notAuthorized
    /// No fix within the timeout, or the system could not determine one. Android's
    /// "Could not get location" (`getCurrentLocation` resolving null).
    case unavailable
    /// Any other Core Location error, carried for Android's "Location error: %1$s".
    case failed(String)
}

@DependencyClient
struct LocationClient {
    /// Already granted (When-In-Use or Always). No prompt needed.
    var isAuthorized: @Sendable () -> Bool = { false }

    /// Presents the system prompt on first ask and resolves to the user's answer. A previous
    /// denial, or a restriction, resolves false without a prompt (iOS only ever asks once).
    var requestAuthorization: @Sendable () async -> Bool = { false }

    /// One fix, or a `LocationFailure`. Bounded by a timeout so the composer cannot hang.
    var currentLocation: @Sendable () async throws -> LocationFix
}
