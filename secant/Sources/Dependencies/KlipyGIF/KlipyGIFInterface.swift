//
//  KlipyGIFInterface.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

extension DependencyValues {
    var klipyGIF: KlipyGIFClient {
        get { self[KlipyGIFClient.self] }
        set { self[KlipyGIFClient.self] = newValue }
    }
}

@DependencyClient
struct KlipyGIFClient {
    /// False when `PartnerKeys.plist` carries no `klipyKey`, which hides the composer's GIF button
    /// rather than offering a search that cannot answer.
    var isConfigured: @Sendable () -> Bool = { false }
    var trending: @Sendable () async throws -> [KlipyGIF]
    var search: @Sendable (_ query: String) async throws -> [KlipyGIF]
    /// Grid-sized rendition, cached across redraws.
    var preview: @Sendable (_ gif: KlipyGIF) async throws -> Data
    /// The sendable rendition, written to a temporary file for `ChatMediaEncoder`.
    var download: @Sendable (_ gif: KlipyGIF) async throws -> URL
}

struct KlipyGIF: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let previewURL: String
    let sendURL: String
    let width: Int
    let height: Int

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }

        return Double(width) / Double(height)
    }
}

enum KlipyGIFError: Error, Equatable {
    case notConfigured
    case badResponse
    case tooLarge
}
