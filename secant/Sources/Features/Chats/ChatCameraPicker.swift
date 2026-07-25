//
//  ChatCameraPicker.swift
//  Zapp
//
//  Camera capture for the chat composer — the iOS counterpart of Android's
//  `CameraCaptureState` + `ActivityResultContracts.TakePicture()`.
//
//  Presented only after `CameraCaptureClient` reports the device has a camera AND the user
//  has granted access; `UIImagePickerController` traps if it is shown with `.camera` on a
//  device that has none.
//

import SwiftUI
import UIKit

struct ChatCameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        }

        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Handed over at full quality; `ChatMediaEncoder` owns the downsample + re-encode so
            // a capture ships at the same size as a picked photo (Android compresses too).
            let image = info[.originalImage] as? UIImage

            guard let data = image?.jpegData(compressionQuality: 1) else {
                onCancel()
                return
            }

            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
