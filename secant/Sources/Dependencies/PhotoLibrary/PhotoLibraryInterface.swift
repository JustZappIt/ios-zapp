//
//  PhotoLibraryInterface.swift
//  Zapp
//
//  Writing an image the user received into their photo library — the counterpart of Android's
//  `saveImageToGallery` in `ImageViewerOverlay.kt`, which inserts into `MediaStore.Images`.
//
//  Add-only: the app never READS the library through this client (the composer's picker uses
//  `PhotosPicker`, which needs no authorization at all), so the live implementation asks for
//  `.addOnly` access and the app declares `NSPhotoLibraryAddUsageDescription` rather than the
//  full-library string.
//

import ComposableArchitecture
import Foundation

extension DependencyValues {
    var photoLibrary: PhotoLibraryClient {
        get { self[PhotoLibraryClient.self] }
        set { self[PhotoLibraryClient.self] = newValue }
    }
}

@DependencyClient
struct PhotoLibraryClient {
    /// Copies the file at `url` into the photo library, prompting for add-only access the first
    /// time. Throws `PhotoLibraryError.notAuthorized` when the user has refused — iOS never
    /// re-prompts, so the caller has to surface that rather than wait on a dialog.
    var saveImage: @Sendable (URL) async throws -> Void
}

enum PhotoLibraryError: Error, Equatable {
    case notAuthorized
    case saveFailed
}
