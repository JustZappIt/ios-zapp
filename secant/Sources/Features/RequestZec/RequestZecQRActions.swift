//
//  RequestZecQRActions.swift
//  Zapp
//
//  The two actions under the Request QR, after Android's `RequestQrCodeView.kt`: "Save QR to
//  Photos" and "Send in chat". Kept beside `RequestZecStore` rather than in it so the QR page's own
//  layout and flow can change without touching these.
//

import ComposableArchitecture
import Foundation
import UIKit
import ZappMessaging

extension RequestZec {
    enum QRSaveOutcome: Equatable {
        case saving
        case saved
        case failed
        /// Add-only access refused. iOS never re-prompts, so this stays up until the next tap.
        case notAuthorized
    }

    enum QRSaveNoticeID: Hashable {
        case expiry
    }

    static let qrSaveNoticeSeconds = 2

    func qrActionsReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
                // MARK: Send in chat

            case .sendInChatTapped:
                guard state.chatPicker == nil else { return .none }

                state.chatPicker = RequestChatPicker.State(
                    request: RequestChatPicker.Request(
                        requesterAddress: state.address.data,
                        zecAmount: state.requestedZec.decimalValue.decimalValue,
                        memo: state.memoState.text,
                        typedFiatAmount: state.requestedFiat
                    )
                )
                return .none

                // Android's `dismissChatPicker`: a dismiss while the request is in flight is ignored,
                // so the result is never lost behind a closed sheet.
            case .chatPickerDismissRequested:
                guard state.chatPicker?.isSending != true else { return .none }

                state.chatPicker = nil
                return .none

            case .chatPicker(.delegate(.sent(let conversation))):
                state.chatPicker = nil
                return .send(.sentInChat(conversation))

            case .chatPicker:
                return .none

            case .sentInChat:
                return .none

                // MARK: Save QR to Photos

            case .saveQRTapped:
                guard state.qrSaveOutcome != .saving, let output = state.encryptedOutput else { return .none }

                state.qrSaveOutcome = .saving

                return .run { [maxPrivacy = state.maxPrivacy] send in
                    guard let png = await Self.savableQRImage(from: output, maxPrivacy: maxPrivacy) else {
                        await send(.qrSaveFinished(.failed))
                        return
                    }

                    do {
                        try await photoLibrary.saveImageData(png)
                        await send(.qrSaveFinished(.saved))
                    } catch PhotoLibraryError.notAuthorized {
                        await send(.qrSaveFinished(.notAuthorized))
                    } catch {
                        await send(.qrSaveFinished(.failed))
                    }
                }

            case .qrSaveFinished(let outcome):
                state.qrSaveOutcome = outcome

                guard outcome == .saved || outcome == .failed else { return .none }

                return .run { send in
                    try await clock.sleep(for: .seconds(Self.qrSaveNoticeSeconds))
                    await send(.qrSaveNoticeExpired)
                }
                .cancellable(id: QRSaveNoticeID.expiry, cancelInFlight: true)

            case .qrSaveNoticeExpired:
                if state.qrSaveOutcome == .saved || state.qrSaveOutcome == .failed {
                    state.qrSaveOutcome = nil
                }
                return .none

            default:
                return .none
            }
        }
    }

    /// The same black-on-white QR with the centre logo that "Share QR Code" hands out, which is
    /// also what Android's `ShareQRUseCase` renders for this button (white background, black
    /// modules, ZEC icon in the middle).
    static func savableQRImage(from output: String, maxPrivacy: Bool) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            QRCodeGenerator.generateCode(from: output, maxPrivacy: maxPrivacy, vendor: .zashi, color: .black)
                .flatMap { withQuietZone($0).pngData() }
        }
        .value
    }

    /// The generator leaves about one module of margin, which is fine inside the app's white card
    /// but not for a picture viewed or printed on its own: scanners want a white quiet zone. This
    /// adds one of 8% per side (about four modules at typical request sizes; Android's has two).
    static func withQuietZone(_ code: CGImage) -> UIImage {
        let side = CGFloat(max(code.width, code.height))
        let inset = (side * 0.08).rounded()
        let canvas = CGSize(width: side + 2 * inset, height: side + 2 * inset)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            UIImage(cgImage: code).draw(in: CGRect(x: inset, y: inset, width: side, height: side))
        }
    }
}
