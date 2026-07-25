//
//  ChatRoomAttachments.swift
//  Zapp
//
//  The composer's "+" menu — Android's `AttachmentSheet` + `MediaAttachmentSheet`
//  (`ChatRoomVM.onAttach*`, `onTakePhoto`, `onFilePicked`, `onShareAddress`, `onSendZec`).
//
//  Kept beside `ChatRoomStore` rather than inside it: the room's reducer body is already at
//  its length budget, and every action here is one self-contained branch of the same menu.
//
//  Presentation note — iOS cannot stack a picker on top of a sheet that is still on screen,
//  so a chosen option is PARKED in `pendingAttachment`, the sheet closes, and the picker is
//  promoted in `.attachmentSheetClosed` (fired from `.sheet(onDismiss:)`, i.e. after the
//  dismissal has actually finished). Android has no such constraint and dismisses/presents
//  in one step.
//

import ComposableArchitecture
import Foundation
import UIKit
import UniformTypeIdentifiers
import ZappMessaging

extension ChatRoom {
    /// Which page the one attachment sheet is showing. Android uses two separate sheets; a
    /// single sheet whose content swaps avoids iOS's sheet-over-sheet dismissal race while
    /// presenting the same two steps.
    enum AttachmentPage: Equatable {
        case actions
        case media
    }

    /// A picker the user asked for that cannot be presented until the sheet is gone.
    enum PendingAttachment: Equatable {
        case photos
        case file
        case camera
    }

    // One branch per menu action; splitting the switch would scatter the menu rather than
    // simplify it (same call as `VotingHelpers`).
    // swiftlint:disable:next cyclomatic_complexity
    func attachmentReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .attachTapped:
                state.attachmentPage = .actions
                state.showsAttachmentSheet = true
                return .none

            case .attachmentSheetDismissed:
                state.showsAttachmentSheet = false
                return .none

            // Fires once the sheet is off screen, which is the first moment a picker can be
            // presented without the system silently dropping it.
            case .attachmentSheetClosed:
                guard let pending = state.pendingAttachment else { return .none }

                state.pendingAttachment = nil
                state.attachmentPage = .actions

                switch pending {
                case .photos:
                    state.showsPhotosPicker = true
                    return .none

                case .file:
                    state.showsFileImporter = true
                    return .none

                case .camera:
                    return .run { send in
                        guard cameraCapture.isAvailable() else {
                            await send(.cameraUnavailable)
                            return
                        }

                        let granted = cameraCapture.isAuthorized()
                            ? true
                            : await cameraCapture.requestAuthorization()

                        await send(.cameraAuthorizationResolved(granted))
                    }
                }

            case .attachMediaTapped:
                state.attachmentPage = .media
                return .none

            case .chooseMediaTapped:
                state.pendingAttachment = .photos
                state.showsAttachmentSheet = false
                return .none

            case .attachFileTapped:
                state.pendingAttachment = .file
                state.showsAttachmentSheet = false
                return .none

            case .takePhotoTapped:
                state.pendingAttachment = .camera
                state.showsAttachmentSheet = false
                return .none

            case .photosPickerDismissed:
                state.showsPhotosPicker = false
                return .none

            case .fileImporterDismissed:
                state.showsFileImporter = false
                return .none

            case .cameraAuthorizationResolved(let granted):
                guard granted else {
                    state.sendDidFail = true
                    state.sendFailureMessage = String(localizable: .chatRoomCameraPermissionRequired)
                    return .none
                }

                state.showsCamera = true
                return .none

            case .cameraUnavailable:
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomCameraUnavailable)
                return .none

            case .cameraDismissed:
                state.showsCamera = false
                return .none

            case .cameraCaptured(let data):
                state.showsCamera = false
                state.sendDidFail = false
                let conversationId = state.conversationId

                return .run { send in
                    // Android compresses a capture to `IMAGE_JPEG` before sending
                    // (`sendCameraCapture`); the encoder does the same re-encode here.
                    let encoded = try ChatMediaEncoder.encode(data, supportedTypes: [UTType.jpeg])
                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        "",
                        encoded.thumbnail
                    )
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send camera capture: \(error)")
                    await send(.mediaSendFailed)
                }

            case .fileImported(let url):
                state.showsFileImporter = false
                state.sendDidFail = false
                let conversationId = state.conversationId

                return .run { send in
                    let encoded = try ChatFileEncoder.encode(url)
                    // The file name travels in the CAPTION — that is where Android puts it
                    // (`sendFileFromUri`) and where its `FileBubble` reads it back from.
                    let message = try await zappMessaging.sendMedia(
                        conversationId,
                        encoded.path,
                        encoded.contentType,
                        encoded.fileName,
                        encoded.thumbnail
                    )
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send file: \(error)")
                    await send(.mediaSendFailed)
                }

            case .shareAddressTapped:
                state.showsAttachmentSheet = false

                guard let address = state.zashiWalletAccount?.unifiedAddress, !address.isEmpty else {
                    state.sendDidFail = true
                    state.sendFailureMessage = String(localizable: .chatRoomShareAddressFailed)
                    return .none
                }

                state.sendDidFail = false
                state.sendFailureMessage = nil
                let conversationId = state.conversationId

                return .run { send in
                    let message = try await zappMessaging.sendWalletAddress(conversationId, address)
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to share wallet address: \(error)")
                    await send(.shareAddressFailed)
                }

            case .shareAddressFailed:
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomShareAddressFailed)
                return .none

            // Root opens the send flow prefilled, reading `resolvedPeerWalletAddress`. With no
            // address to prefill there is nothing to send to, so the room offers the scanner
            // instead — Android reaches the same scan from its send-ZEC path.
            case .sendZecTapped:
                state.showsAttachmentSheet = false

                return state.resolvedPeerWalletAddress == nil
                    ? .send(.scanWalletAddressTapped)
                    : .none

            case .scanWalletAddressTapped:
                state.showsAttachmentSheet = false
                return .none

            default:
                return .none
            }
        }
    }
}

// MARK: - Peer address resolution

extension ChatRoom.State {
    /// The newest address the peer posted into THIS chat. Android's `resolvePeerWalletAddress()`
    /// reads the same last-wins wallet-address message.
    var peerSharedWalletAddress: String? {
        messages
            .last { !$0.isFromMe && $0.contentType == ChatContentType.walletAddress }
            .map(\.content)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The peer's saved address-book row, so Send ZEC prefills for a saved contact who has not
    /// shared anything in-chat yet (Android's `resolveSavedContactAddress()`).
    ///
    /// A conversation can carry OUR key among its participants, so our own key is excluded
    /// before the lookup — the same trap `resolvedDisplayName` documents.
    var savedContactWalletAddress: String? {
        guard let conversation, conversation.type == .direct else { return nil }

        let ownKey = messagingState.identity.map { PublicKeyRules.sanitize($0.publicKey) }

        return conversation.participantIds
            .lazy
            .filter { PublicKeyRules.sanitize($0) != ownKey }
            .compactMap { chatContacts.contact(for: $0)?.address }
            .first { !$0.isEmpty }
    }

    var resolvedPeerWalletAddress: String? {
        peerSharedWalletAddress ?? savedContactWalletAddress
    }
}

// MARK: - File encoding

/// Turns a document-picker URL into something the core can ship. Unlike a picked photo, a file
/// is forwarded BYTE-FOR-BYTE (Android's `sendFileFromUri` only copies it into its cache) —
/// re-encoding a document would corrupt it.
enum ChatFileEncoder {
    struct Encoded: Equatable {
        let path: String
        let contentType: String
        let fileName: String
        let thumbnail: String?
    }

    enum Failure: Error {
        case unreadable
    }

    private static let fallbackContentType = "application/octet-stream"
    private static let thumbnailPixel: CGFloat = 64
    private static let thumbnailQuality: CGFloat = 0.5

    static func encode(_ url: URL) throws -> Encoded {
        // A document handed over by `fileImporter` lives outside the app sandbox and is only
        // readable inside this scope.
        let isScoped = url.startAccessingSecurityScopedResource()

        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }

        let fileName = url.lastPathComponent.isEmpty
            ? String(localizable: .chatRoomMediaFile)
            : url.lastPathComponent

        let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? fallbackContentType

        let thumbnail = contentType.hasPrefix(ChatContentType.imagePrefix)
            ? ChatMediaImage
                .downsampled(data: data, maxPixel: thumbnailPixel)?
                .jpegData(compressionQuality: thumbnailQuality)?
                .base64EncodedString()
            : nil

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("zapp-file-\(UUID().uuidString)-\(fileName)")

        try data.write(to: destination, options: .atomic)

        return Encoded(
            path: destination.path,
            contentType: contentType,
            fileName: fileName,
            thumbnail: thumbnail
        )
    }
}
