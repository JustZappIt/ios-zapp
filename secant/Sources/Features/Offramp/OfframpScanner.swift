// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

struct OfframpScanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    @State private var showLibrary = false

    let title: String
    let errorMessage: String?
    let isLoading: Bool
    let checkpointMessage: String?
    let onCode: (String) -> Void
    let onPhotoFailure: () -> Void
    let onResumeCheckpoint: () -> Void
    let onDiscardCheckpoint: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            if showLibrary {
                ZashiImagePicker(selectedImage: $image, showSheet: $showLibrary)
            } else {
                GeometryReader { proxy in
                    QRCodeScanView(
                        rectOfInterest: ScanView.normalizedRectsOfInterest(1).real,
                        onQRScanningDidFail: { },
                        onQRScanningSucceededWithCode: onCode
                    )
                    scannerFrame(proxy.size)
                }
                VStack(spacing: 0) {
                    Text(title)
                        .zappFont(.sectionTitle, color: .white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 60)
                    if let errorMessage {
                        Text(errorMessage)
                            .zappFont(.caption, color: .white)
                            .padding(12)
                            .background(Color.black.opacity(0.65))
                            .padding(.top, 12)
                    }
                    Spacer()
                    if let checkpointMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(checkpointMessage)
                                .zappFont(.body, style: ZappColors.text)
                            HStack(spacing: 10) {
                                ZappButton(
                                    title: String(localized: "offramp.checkpoint.discard", defaultValue: "Discard"),
                                    variant: .danger,
                                    action: onDiscardCheckpoint
                                )
                                ZappButton(
                                    title: String(localized: "offramp.checkpoint.resume", defaultValue: "Resume"),
                                    action: onResumeCheckpoint
                                )
                            }
                        }
                        .padding(16)
                        .background(ZappColors.surface.color(colorScheme))
                        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                    }
                    HStack(spacing: 12) {
                        ZappBackButton(tint: .onAccent, action: onBack)
                        ZappButton(
                            title: String(localized: "offramp.scan.library", defaultValue: "Photo library"),
                            isEnabled: checkpointMessage == nil
                        ) {
                            showLibrary = true
                        }
                    }
                    .padding(18)
                }
                if isLoading {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: image) { image in
            guard let image else { return }
            guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil),
                  let ciImage = CIImage(image: image),
                  let code = detector.features(in: ciImage).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first
            else {
                onPhotoFailure()
                self.image = nil
                return
            }
            onCode(code)
            self.image = nil
        }
    }

    private func scannerFrame(_ size: CGSize) -> some View {
        let rect = ScanView.rectOfInterest(size, 1)
        return ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .reverseMask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}
