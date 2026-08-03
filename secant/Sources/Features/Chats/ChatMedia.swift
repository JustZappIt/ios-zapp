//
//  ChatMedia.swift
//  Zapp
//

import CoreTransferable
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Turns a picked photo into something the core can ship: a file on disk, a MIME type the peer
/// can actually decode, and a wire thumbnail small enough to ride inside the message body.
enum ChatMediaEncoder {
    struct Encoded: Equatable {
        let path: String
        let contentType: String
        let thumbnail: String?
    }

    enum Failure: Error, Equatable {
        case undecodable
        case tooLarge
    }

    private static let maxPixel: CGFloat = 1920
    private static let quality: CGFloat = 0.85
    static let maxInputBytes = 32 * 1024 * 1024
    private static let maxEncodedBytes = 12 * 1024 * 1024

    /// A GIF ships verbatim, so nothing downsizes it on the way out.
    static let maxGIFBytes = 8 * 1024 * 1024

    /// The thumbnail travels ON THE WIRE inside the message, so it stays tiny.
    private static let thumbnailPixel: CGFloat = 64
    private static let thumbnailQuality: CGFloat = 0.5

    static func encode(fileURL: URL, supportedTypes: [UTType]) throws -> Encoded {
        guard
            let byteCount = ChatMediaImage.fileByteCount(at: fileURL),
            byteCount > 0,
            byteCount <= maxInputBytes
        else {
            throw Failure.tooLarge
        }

        let isGIF = ChatMediaImage.isGIF(at: fileURL)

        // Reject oversized GIFs before ImageIO sees a byte. They ship verbatim and therefore
        // cannot become smaller later in this pipeline.
        if isGIF, byteCount > maxGIFBytes {
            throw Failure.tooLarge
        }

        guard let thumbnailImage = ChatMediaImage.downsampled(path: fileURL.path, maxPixel: thumbnailPixel) else {
            throw Failure.undecodable
        }

        let thumbnail = thumbnailImage
            .jpegData(compressionQuality: thumbnailQuality)?
            .base64EncodedString()

        // Re-encoding a GIF collapses it to one frame. Sniffed from the bytes: PhotosUI
        // advertises a conforming still representation for an animated asset.
        if isGIF {
            return Encoded(
                path: try copy(fileURL, pathExtension: "gif"),
                contentType: "image/gif",
                thumbnail: thumbnail
            )
        }

        // Match Android's strict image path: every non-GIF still is downsampled and re-encoded.
        // Forwarding PNG verbatim allowed a highly-compressed source to bypass output bounds and
        // reach the worklet as a multi-megabyte allocation.
        _ = supportedTypes
        guard let jpeg = ChatMediaImage
            .downsampled(path: fileURL.path, maxPixel: maxPixel)?
            .jpegData(compressionQuality: quality)
        else {
            throw Failure.undecodable
        }
        guard jpeg.count <= maxEncodedBytes else { throw Failure.tooLarge }

        return Encoded(
            path: try write(jpeg, pathExtension: "jpg"),
            contentType: "image/jpeg",
            thumbnail: thumbnail
        )
    }

    private static func write(_ data: Data, pathExtension: String) throws -> String {
        let url = ChatMediaTemporaryFiles.makeURL(pathExtension: pathExtension)

        try data.write(to: url, options: .atomic)

        return url.path
    }

    private static func copy(_ sourceURL: URL, pathExtension: String) throws -> String {
        let destinationURL = ChatMediaTemporaryFiles.makeURL(pathExtension: pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.path
    }
}

struct ChatPickedMedia: Transferable, Sendable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            ChatPickedMedia(fileURL: try ChatMediaTemporaryFiles.importFile(at: received.file))
        }
    }
}

enum ChatMediaTemporaryFiles {
    static func makeURL(pathExtension: String) -> URL {
        let sanitizedExtension = pathExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let suffix = sanitizedExtension.isEmpty ? "bin" : sanitizedExtension

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("zapp-media-\(UUID().uuidString).\(suffix)")
    }

    static func importFile(at sourceURL: URL) throws -> URL {
        guard
            let byteCount = ChatMediaImage.fileByteCount(at: sourceURL),
            byteCount > 0,
            byteCount <= ChatMediaEncoder.maxInputBytes
        else {
            throw ChatMediaEncoder.Failure.tooLarge
        }

        let destinationURL = makeURL(pathExtension: sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func remove(_ url: URL) {
        guard url.isFileURL else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            LoggerProxy.warn("Chat media temporary-file cleanup failed: \(error.localizedDescription)")
        }
    }
}
