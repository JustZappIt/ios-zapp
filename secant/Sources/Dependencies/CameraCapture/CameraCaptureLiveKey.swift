//
//  CameraCaptureLiveKey.swift
//  Zapp
//

@preconcurrency import AVFoundation
import ComposableArchitecture

extension CameraCaptureClient: DependencyKey {
    static let liveValue = Self(
        isAvailable: {
            AVCaptureDevice.default(for: .video) != nil
        },
        isAuthorized: {
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        },
        requestAuthorization: {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                return true
            case .notDetermined:
                return await AVCaptureDevice.requestAccess(for: .video)
            default:
                // Denied or restricted. iOS never re-prompts, so the caller has to surface
                // the refusal rather than wait on a dialog that will not appear.
                return false
            }
        }
    )
}

extension CameraCaptureClient {
    static let noOp = Self(
        isAvailable: { false },
        isAuthorized: { false },
        requestAuthorization: { false }
    )
}
