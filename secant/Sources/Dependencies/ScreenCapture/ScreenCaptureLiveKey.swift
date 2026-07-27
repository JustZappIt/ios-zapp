//
//  ScreenCaptureLiveKey.swift
//  Zapp
//

import ComposableArchitecture
import UIKit

extension ScreenCaptureClient: DependencyKey {
    static let liveValue = Self(
        // `UIScreen.main` is the same screen the `capturedDidChange` observers watch, so the
        // one-shot check and the notification agree on what "the screen" means.
        isCaptured: {
            UIScreen.main.isCaptured
        }
    )
}

extension ScreenCaptureClient {
    static let noOp = Self(isCaptured: { false })
}
