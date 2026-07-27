//
//  ScreenCaptureInterface.swift
//  Zapp
//
//  Whether the screen is being recorded, mirrored or captured RIGHT NOW.
//
//  The secret surfaces already react to `UIScreen.capturedDidChangeNotification`, which only
//  fires on a TRANSITION. A recording that was already running before the screen opened never
//  produces one, so every reveal also has to ask the question outright — that is what this
//  client is for. Wrapped rather than read inline so the refusal is testable without a device.
//

import ComposableArchitecture

extension DependencyValues {
    var screenCapture: ScreenCaptureClient {
        get { self[ScreenCaptureClient.self] }
        set { self[ScreenCaptureClient.self] = newValue }
    }
}

@DependencyClient
struct ScreenCaptureClient {
    /// True while the screen is recorded, AirPlay-mirrored, or otherwise captured.
    var isCaptured: @Sendable () -> Bool = { false }
}
