//
//  PhotoLibraryLiveKey.swift
//  Zapp
//

import ComposableArchitecture
import Foundation
@preconcurrency import Photos

extension PhotoLibraryClient: DependencyKey {
    static let liveValue = Self(
        saveImage: { url in
            guard await requestAddOnlyAccess() else { throw PhotoLibraryError.notAuthorized }

            // `addResource(with:fileURL:)` hands the ORIGINAL bytes to Photos rather than a
            // re-encode of a decoded `UIImage`, so the saved file is the file the peer sent —
            // the same guarantee Android's stream copy gives.
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .photo, fileURL: url, options: options)
                }
            } catch {
                LoggerProxy.error("PhotoLibrary: save to library failed")
                throw PhotoLibraryError.saveFailed
            }
        }
    )

    private static func requestAddOnlyAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true

        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited

        default:
            return false
        }
    }
}

extension PhotoLibraryClient {
    static let noOp = Self(saveImage: { _ in })
}
