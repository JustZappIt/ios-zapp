//
//  ChatVideoTests.swift
//  zodlTests
//
//  Video in chat: what the picker hands the encoder, what reaches the core (`video/mp4`, at most
//  the core's 32 MB `MEDIA_MAX_BYTES`), and how an incoming Android video is classified.
//

import AVFoundation
import ComposableArchitecture
import CoreVideo
import Foundation
import Testing
import UniformTypeIdentifiers
import ZappMessaging
@testable import zodl_internal

@Suite struct ChatVideoTests {
    // MARK: - Picker classification

    @Test func moviesAreVideosAndLivePhotosStayPhotos() {
        #expect(ChatVideoEncoder.isVideo([.quickTimeMovie]))
        #expect(ChatVideoEncoder.isVideo([.mpeg4Movie]))
        #expect(!ChatVideoEncoder.isVideo([.jpeg]))
        #expect(!ChatVideoEncoder.isVideo([.gif]))
        // A Live Photo offers its still alongside the movie and must keep the photo path.
        #expect(!ChatVideoEncoder.isVideo([.heic, .quickTimeMovie]))
    }

    // MARK: - Wire

    /// Android's camera recordings travel as `video/mp4`, and the core stores the file under the
    /// subtype as its extension; `mp4` is the only video extension `media-store.js` serves.
    @Test func videosGoOutAsMp4() {
        #expect(ChatVideoEncoder.contentType == "video/mp4")
        #expect(ChatVideoEncoder.contentType.hasPrefix(ChatContentType.videoPrefix))
        #expect(ChatVideoEncoder.contentType.components(separatedBy: "/").last == "mp4")
    }

    @Test func incomingVideosClassifyAsVideoWhateverTheContainer() {
        for type in ["video/mp4", "video/quicktime", "video/3gpp"] {
            let message = ZMMessage(
                id: type,
                conversationId: "c",
                senderId: "peer",
                content: "",
                contentType: type,
                isFromMe: false,
                mediaId: "m"
            )

            #expect(ChatMessageKind.of(message) == .video, "\(type)")
        }
    }

    // MARK: - Size limit

    @Test func theCapIsTheCoresMediaLimit() throws {
        #expect(ChatVideoEncoder.maxBytes == 32 * 1024 * 1024)

        try ChatVideoEncoder.checkSize(Int64(ChatVideoEncoder.maxBytes))
        #expect(throws: ChatVideoEncoder.Failure.tooLarge) {
            try ChatVideoEncoder.checkSize(Int64(ChatVideoEncoder.maxBytes) + 1)
        }
        #expect(throws: ChatVideoEncoder.Failure.tooLarge) {
            try ChatVideoEncoder.checkSize(0)
        }
    }

    @MainActor @Test func anOversizedVideoIsRefusedWithItsOwnCopy() async {
        var state = ChatRoom.State(conversationId: "conversation")
        state.isSendingMedia = true

        let store = TestStore(initialState: state) {
            ChatRoom()
        }

        await store.send(.attachmentFailed(String(localizable: .chatRoomVideoTooLarge))) {
            $0.isSendingMedia = false
            $0.sendDidFail = true
            $0.sendFailureMessage = "That video is too large to send."
        }
    }

    // MARK: - Export

    /// A QuickTime recording comes out as an MP4 file (an `ftyp` box whose brand is not
    /// QuickTime's `qt  `), with a wire thumbnail of its first frame.
    @Test func aQuickTimeMovieIsExportedToMp4WithAThumbnail() async throws {
        let source = try await makeMovie()
        defer { try? FileManager.default.removeItem(at: source) }

        let encoded = try await ChatVideoEncoder.encode(source)
        defer { try? FileManager.default.removeItem(atPath: encoded.path) }

        let data = try Data(contentsOf: URL(fileURLWithPath: encoded.path))
        #expect(encoded.path.hasSuffix(".mp4"))
        #expect(data.count > 12)
        #expect(String(decoding: data[4..<8], as: UTF8.self) == "ftyp")
        #expect(String(decoding: data[8..<12], as: UTF8.self) != "qt  ")
        #expect(encoded.thumbnail?.isEmpty == false)
    }

    private func makeMovie() async throws -> URL {
        let width = 64
        let height = 48
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zapp-test-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }

            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try #require(buffer)

            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 20), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])

            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)

        return url
    }
}
