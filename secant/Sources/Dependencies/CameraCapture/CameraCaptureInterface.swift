//
//  CameraCaptureInterface.swift
//  Zapp
//
//  Camera permission + availability for the chat composer's "Camera" attachment.
//  `CaptureDeviceClient` covers the QR scanner's already-authorized/torch needs; taking a
//  photo additionally has to be able to ASK, which is what this client adds.
//

import ComposableArchitecture

extension DependencyValues {
    var cameraCapture: CameraCaptureClient {
        get { self[CameraCaptureClient.self] }
        set { self[CameraCaptureClient.self] = newValue }
    }
}

@DependencyClient
struct CameraCaptureClient {
    /// False where there is no camera at all (Simulator), so the option can fail quietly
    /// instead of presenting an empty picker.
    var isAvailable: @Sendable () -> Bool = { false }

    /// Already granted — no prompt needed.
    var isAuthorized: @Sendable () -> Bool = { false }

    /// Presents the system prompt on first ask and resolves to the user's answer. A previous
    /// denial resolves false without a second prompt (iOS only ever asks once).
    var requestAuthorization: @Sendable () async -> Bool = { false }
}
