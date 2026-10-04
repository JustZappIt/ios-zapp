//
//  ChatVideo.swift
//  Zapp
//
//  Sending a video picked from the library. Android's `sendMediaFromUri` copies the picked file
//  and posts it under its own MIME type with no thumbnail. iOS cannot ship the library file as-is:
//  an iPhone recording is a QuickTime movie, and the core only serves stored media whose extension
//  is jpg/jpeg/png/gif/mp4 (`media-store.js: getMedia`). A `video/quicktime` send would be stored as
//  `.quicktime` and never reach the peer. So every pick is exported to H.264/AAC MP4 and posted as
//  `video/mp4`, the type an Android camera recording carries.
//

@preconcurrency import AVFoundation
import ComposableArchitecture
import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ChatVideoEncoder {
    struct Encoded: Equatable {
        let path: String
        let thumbnail: String?
    }

    enum Failure: Error, Equatable {
        case undecodable
        case tooLarge
        case exportFailed
    }

    static let contentType = "video/mp4"

    /// The core's `MEDIA_MAX_BYTES`. Android has no check of its own; the core rejects a bigger
    /// file with a generic error that Android only logs. iOS refuses it up front with its own copy.
    static let maxBytes = 32 * 1024 * 1024

    /// H.264 at up to 720p: decodable by every Android device, and small enough that a typical
    /// clip of up to about a minute fits under `maxBytes`. 720p is a ceiling; smaller sources
    /// are not upscaled.
    private static let preset = AVAssetExportPreset1280x720

    /// Same wire thumbnail as a picked photo (`ChatMediaEncoder`): tiny, because it travels
    /// inside the message body. Android sends none for video; a peer that reads it gets a poster
    /// while the file transfers.
    private static let thumbnailPixel: CGFloat = 64
    private static let thumbnailQuality: CGFloat = 0.5

    /// A picker item is a video when it offers a movie and no still. A Live Photo offers both
    /// and stays a photo.
    static func isVideo(_ types: [UTType]) -> Bool {
        types.contains { $0.conforms(to: .movie) } && !types.contains { $0.conforms(to: .image) }
    }

    static func checkSize(_ byteCount: Int64) throws {
        guard byteCount > 0, byteCount <= Int64(maxBytes) else { throw Failure.tooLarge }
    }

    static func encode(_ sourceURL: URL) async throws -> Encoded {
        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.undecodable
        }

        let destination = ChatMediaTemporaryFiles.makeURL(pathExtension: "mp4")
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        // Refuse an obviously oversized clip before spending a long export on it. The estimate is
        // rough (and needs the file type set first), so it only rules out a clip at twice the cap;
        // the exported file is what is checked against the cap itself.
        let estimate = await estimatedLength(of: session)
        if estimate > 2 * Int64(maxBytes) {
            throw Failure.tooLarge
        }

        do {
            try await export(session)

            guard let byteCount = ChatMediaImage.fileByteCount(at: destination) else { throw Failure.exportFailed }
            try checkSize(Int64(byteCount))
        } catch {
            ChatMediaTemporaryFiles.remove(destination)
            throw error
        }

        return Encoded(path: destination.path, thumbnail: await thumbnail(of: asset))
    }

    /// Zero when the session cannot estimate.
    private static func estimatedLength(of session: AVAssetExportSession) async -> Int64 {
        await withCheckedContinuation { continuation in
            session.estimateOutputFileLength { length, _ in
                continuation.resume(returning: length)
            }
        }
    }

    /// A cancelled effect stops the export rather than letting it run on.
    private static func export(_ session: AVAssetExportSession) async throws {
        try await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            session.cancelExport()
        }

        try Task.checkCancellation()

        guard session.status == .completed else {
            LoggerProxy.error("Chat video export failed: \(String(describing: session.error))")
            throw Failure.exportFailed
        }
    }

    private static func thumbnail(of asset: AVAsset) async -> String? {
        guard let frame = await ChatVideoFrame.first(of: asset, maxPixel: thumbnailPixel) else { return nil }

        return UIImage(cgImage: frame)
            .jpegData(compressionQuality: thumbnailQuality)?
            .base64EncodedString()
    }
}

/// The first frame of a video, already oriented and downsampled. Shared by the sender's wire
/// thumbnail and the bubble's poster.
enum ChatVideoFrame {
    static func first(of asset: AVAsset, maxPixel: CGFloat) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)

        return try? await generator.image(at: .zero).image
    }
}

struct ChatPickedVideo: Transferable, Sendable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            // The received file is only valid inside this closure. A same-volume copy is a clone,
            // so a long clip costs no extra space before the export shrinks it.
            let destination = ChatMediaTemporaryFiles.makeURL(pathExtension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)

            return ChatPickedVideo(fileURL: destination)
        }
    }
}

extension ChatRoom {
    func sendPickedVideo(_ item: PhotosPickerItem, conversationId: String) -> Effect<Action> {
        .run { send in
            guard let picked = try await item.loadTransferable(type: ChatPickedVideo.self) else {
                await send(.mediaSendFailed)
                return
            }
            defer { ChatMediaTemporaryFiles.remove(picked.fileURL) }

            let encoded = try await ChatVideoEncoder.encode(picked.fileURL)
            defer { ChatMediaTemporaryFiles.remove(URL(fileURLWithPath: encoded.path)) }

            let message = try await zappMessaging.sendMedia(
                conversationId,
                encoded.path,
                ChatVideoEncoder.contentType,
                "",
                encoded.thumbnail
            )
            await send(.mediaSendSucceeded(message))
        } catch: { error, send in
            LoggerProxy.error("Chat room failed to send video: \(error)")

            if error as? ChatVideoEncoder.Failure == .tooLarge {
                await send(.attachmentFailed(String(localizable: .chatRoomVideoTooLarge)))
            } else {
                await send(.mediaSendFailed)
            }
        }
    }
}
