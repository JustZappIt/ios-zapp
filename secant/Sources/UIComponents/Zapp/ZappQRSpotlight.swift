//
//  ZappQRSpotlight.swift
//  Zapp
//

import SwiftUI
import UIKit

private enum ZappQRSpotlightConstants {
    static let scrimOpacity: CGFloat = 0.9
    static let horizontalInset: CGFloat = 32
    static let actionSpacing: CGFloat = 28
    static let actionWidth: CGFloat = 220
}

/// Blows a QR code up over the whole screen — Android's `ZashiQr(fullscreenAction:)` — with the
/// display driven to full brightness so the code still scans from across a table.
///
/// Attach it at the SCREEN ROOT: a scrim nested inside a `ScrollView` cannot be tapped anywhere
/// but its own row.
private struct ZappQRSpotlight<QR: View, Action: View>: ViewModifier {
    private typealias Constants = ZappQRSpotlightConstants

    @Binding var payload: String?
    let qrCode: (String, CGFloat) -> QR
    let action: (String) -> Action

    /// Nil until the spotlight raises brightness, so restoring can never write back a level it
    /// never captured.
    @State private var previousBrightness: CGFloat?

    private var edge: CGFloat {
        let bounds = UIScreen.main.bounds
        return min(bounds.width, bounds.height) - Constants.horizontalInset * 2
    }

    func body(content: Content) -> some View {
        content
            // The page behind is unreachable while the code is up, by touch and by VoiceOver
            // alike. Applied to `content` only, so the overlay below stays readable.
            .accessibilityHidden(payload != nil)
            .overlay {
                if let payload {
                    ZStack {
                        Color.black
                            .opacity(Constants.scrimOpacity)
                            .ignoresSafeArea()
                            .onTapGesture { dismiss() }
                            .accessibilityHidden(true)

                        VStack(spacing: Constants.actionSpacing) {
                            qrCode(payload, edge)
                                .onTapGesture { dismiss() }
                                .accessibilityElement()
                                .accessibilityLabel(String(localizable: .generalClose))
                                .accessibilityAddTraits(.isButton)

                            action(payload)
                                .frame(maxWidth: Constants.actionWidth)
                        }
                    }
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { dismiss() }
                }
            }
            .animation(ZappMotion.content, value: payload)
            .onChange(of: payload) { presented in
                if presented == nil {
                    restoreBrightness()
                } else {
                    brighten()
                }
            }
            // Screen brightness is a DEVICE setting: leaving it at full because the user pressed
            // Home mid-scan would outlive the app. It is re-raised when they come back.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                restoreBrightness()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if payload != nil {
                    brighten()
                }
            }
            .onDisappear(perform: restoreBrightness)
    }

    private func dismiss() {
        payload = nil
    }

    private func brighten() {
        guard previousBrightness == nil else { return }

        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1
    }

    private func restoreBrightness() {
        guard let previousBrightness else { return }

        UIScreen.main.brightness = previousBrightness
        self.previousBrightness = nil
    }
}

extension View {
    /// `payload` doubles as the presentation state: non-nil means the code is up. `qrCode` is handed
    /// that payload and the edge length to draw at, so one call site covers both sizes.
    func zappQRSpotlight<QR: View, Action: View>(
        payload: Binding<String?>,
        @ViewBuilder qrCode: @escaping (String, CGFloat) -> QR,
        @ViewBuilder action: @escaping (String) -> Action
    ) -> some View {
        modifier(ZappQRSpotlight(payload: payload, qrCode: qrCode, action: action))
    }
}
