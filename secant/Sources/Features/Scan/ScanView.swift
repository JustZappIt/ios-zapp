//
//  ScanView.swift
//  Zashi
//
//  Created by Lukáš Korba on 16.05.2022.
//

import SwiftUI
import ComposableArchitecture

struct ScanView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL

    // The scanner chrome sits on a live camera feed, so it is fixed light-on-dark in both themes
    // rather than reading ZappColors, which would flip it to dark-on-dark in light mode.
    private enum Constants {
        static let chromeForeground = Color.white
        static let chromeBackground = Color.black.opacity(0.55)
        static let scrimOpacity: CGFloat = 0.65
        static let controlIconSize: CGFloat = 24
        static let controlBox: CGFloat = 48
        static let controlOffset: CGFloat = 35
        static let controlDrop: CGFloat = 45
        static let progressDrop: CGFloat = 56
    }

    @State private var image: UIImage?
    @State private var showSheet = false

    let store: StoreOf<Scan>
    let popoverRatio: CGFloat

    init(store: StoreOf<Scan>, popoverRatio: CGFloat = 1.0) {
        self.store = store
        self.popoverRatio = popoverRatio
    }

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                if showSheet {
                    ZashiImagePicker(selectedImage: $image, showSheet: $showSheet)
                } else {
                    GeometryReader { proxy in
                        QRCodeScanView(
                            rectOfInterest: ScanView.normalizedRectsOfInterest(popoverRatio).real,
                            onQRScanningDidFail: { store.send(.scanFailed(.invalidQRCode)) },
                            onQRScanningSucceededWithCode: { store.send(.scan($0.redacted)) }
                        )
                        
                        frameOfInterest(proxy.size)
                        
                        WithPerceptionTracking {
                            if store.isTorchAvailable {
                                torchButton(size: proxy.size)
                            }
                            
                            if !store.forceLibraryToHide {
                                libraryButton(size: proxy.size)
                            }
                        }
                        
                        WithPerceptionTracking {
                            if store.progress != nil {
                                WithPerceptionTracking {
                                    progress(size: proxy.size, progress: store.countedProgress)
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: 0) {
                        WithPerceptionTracking {
                            if let instructions = store.instructions {
                                Text(instructions)
                                    .zappFont(.sectionTitle, color: Constants.chromeForeground)
                                    .padding(.top, Design.Spacing._7xl)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.center)
                            }

                            Spacer()

                            if !store.info.isEmpty {
                                HStack(alignment: .top, spacing: Design.Spacing._lg) {
                                    Asset.Assets.infoOutline.image
                                        .zImage(width: 20, height: 20, color: Constants.chromeForeground)

                                    Text(store.info)
                                        .zappFont(.caption, color: Constants.chromeForeground)

                                    Spacer(minLength: 0)
                                }
                                .padding(.bottom, Design.Spacing._xl)
                            }

                            if !store.isCameraEnabled {
                                ZappButton(title: String(localizable: .scanOpenSettings)) {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                }
                                .padding(.bottom, Design.Spacing._5xl)
                            } else {
                                ZappButton(title: String(localizable: .generalCancel)) {
                                    store.send(.cancelTapped)
                                }
                                .padding(.bottom, Design.Spacing._5xl)
                            }
                        }
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .ignoresSafeArea()
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .zashiBackV2(hidden: store.isCameraEnabled, invertedColors: colorScheme == .light) {
                store.send(.cancelTapped)
            }
            .onChange(of: image) { img in
                if let img {
                    store.send(.libraryImage(img))
                }
            }
        }
    }
    
    private func controlButton(icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .zImage(
                    width: Constants.controlIconSize,
                    height: Constants.controlIconSize,
                    color: Constants.chromeForeground
                )
                .frame(width: Constants.controlBox, height: Constants.controlBox)
                .background(Constants.chromeBackground)
        }
        .buttonStyle(.zappPress)
    }

    private func torchButton(size: CGSize) -> some View {
        let topLeft = ScanView.rectOfInterest(size, popoverRatio).origin
        let frameSize = ScanView.frameSize(size, popoverRatio)

        return WithPerceptionTracking {
            controlButton(
                icon: store.isTorchOn
                    ? Asset.Assets.Icons.flashOff.image
                    : Asset.Assets.Icons.flashOn.image
            ) {
                store.send(.torchTapped)
            }
            .position(
                x: topLeft.x + frameSize.width * 0.5
                    + (store.forceLibraryToHide ? 0 : Constants.controlOffset),
                y: topLeft.y + frameSize.height + Constants.controlDrop
            )
        }
    }

    private func libraryButton(size: CGSize) -> some View {
        let topLeft = ScanView.rectOfInterest(size, popoverRatio).origin
        let frameSize = ScanView.frameSize(size, popoverRatio)

        return WithPerceptionTracking {
            controlButton(icon: Asset.Assets.Icons.imageLibrary.image) {
                showSheet = true
            }
            .position(
                x: topLeft.x + frameSize.width * 0.5
                    - (store.isTorchAvailable ? Constants.controlOffset : 0),
                y: topLeft.y + frameSize.height + Constants.controlDrop
            )
        }
    }

    private func progress(size: CGSize, progress: Int) -> some View {
        let topLeft = ScanView.rectOfInterest(size, popoverRatio).origin
        let frameSize = ScanView.frameSize(size, popoverRatio)

        return VStack(spacing: Design.Spacing._xs) {
            Text(String(format: "%d%%", progress))
                .zappFont(.rowTitle, color: Constants.chromeForeground)

            ProgressView(value: Float(progress), total: Float(100))
        }
        .frame(width: frameSize.width * 0.8)
        .tint(ZappColors.accent.color(colorScheme))
        .position(
            x: topLeft.x + frameSize.width * 0.5,
            y: topLeft.y - Constants.progressDrop
        )
    }
}

extension ScanView {
    func frameOfInterest(_ size: CGSize) -> some View {
        let topLeft = ScanView.rectOfInterest(size, popoverRatio).origin
        let frameSize = ScanView.frameSize(size, popoverRatio)
        let sizeOfTheMark = 40.0
        let markShiftSize = 18.0

        return ZStack {
            Color.black
                .opacity(Constants.scrimOpacity)
                .edgesIgnoringSafeArea(.all)
                .ignoresSafeArea()
                .reverseMask(alignment: .topLeading) {
                    Rectangle()
                        .frame(
                            width: frameSize.width,
                            height: frameSize.height,
                            alignment: .topLeading
                        )
                        .offset(
                            x: topLeft.x,
                            y: topLeft.y
                        )
                }

            // top right
            Asset.Assets.scanMark.image
                .resizable()
                .frame(width: sizeOfTheMark, height: sizeOfTheMark)
                .position(
                    x: topLeft.x + frameSize.width - markShiftSize,
                    y: topLeft.y + markShiftSize
                )

            // top left
            Asset.Assets.scanMark.image
                .resizable()
                .frame(width: sizeOfTheMark, height: sizeOfTheMark)
                .rotationEffect(Angle(degrees: 270))
                .position(
                    x: topLeft.x + markShiftSize,
                    y: topLeft.y + markShiftSize
                )

            // bottom left
            Asset.Assets.scanMark.image
                .resizable()
                .frame(width: sizeOfTheMark, height: sizeOfTheMark)
                .rotationEffect(Angle(degrees: 180))
                .position(
                    x: topLeft.x + markShiftSize,
                    y: topLeft.y + frameSize.height - markShiftSize
                )

            // bottom right
            Asset.Assets.scanMark.image
                .resizable()
                .frame(width: sizeOfTheMark, height: sizeOfTheMark)
                .rotationEffect(Angle(degrees: 90))
                .position(
                    x: topLeft.x + frameSize.width - markShiftSize,
                    y: topLeft.y + frameSize.height - markShiftSize
                )
        }
    }
}

extension View {
    @inlinable
    func reverseMask<Mask: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}

extension ScanView {
    static func frameSize(_ size: CGSize, _ popoverRatio: CGFloat) -> CGSize {
        let rect = normalizedRectsOfInterest(popoverRatio).renderOnly
        
        return CGSize(width: rect.width * size.width, height: rect.height * size.height)
    }

    static func rectOfInterest(_ size: CGSize, _ popoverRatio: CGFloat) -> CGRect {
        let rect = normalizedRectsOfInterest(popoverRatio).renderOnly

        return CGRect(
            x: size.width * rect.origin.x,
            y: size.height * rect.origin.y,
            width: frameSize(size, popoverRatio).width,
            height: frameSize(size, popoverRatio).height
        )
    }

    static func normalizedRectsOfInterest(_ popoverRatio: CGFloat) -> (renderOnly: CGRect, real: CGRect) {
        let rect = UIScreen.main.bounds
        
        let readRectSize = 0.6

        let topLeftX = (1.0 - readRectSize) * 0.5
        let ratio = rect.width / rect.height
        let rectHeight = ratio * readRectSize * popoverRatio
        let topLeftY = (1.0 - rectHeight) * 0.5

        return (
            renderOnly: CGRect(
                x: topLeftX,
                y: topLeftY,
                width: readRectSize,
                height: rectHeight
            ), real: CGRect(
                x: topLeftX,
                y: topLeftX,
                width: readRectSize,
                height: readRectSize
            )
        )
    }
}

// MARK: - Previews

struct ScanView_Previews: PreviewProvider {
    static var previews: some View {
        ScanView(store: Scan.placeholder)
    }
}

// MARK: Placeholders

extension Scan.State {
    static var initial: Scan.State { Scan.State() }
}

extension Scan {
    @MainActor static let placeholder = StoreOf<Scan>(
        initialState: .initial
    ) {
        Scan()
    }
}
