//
//  ZappKeyboardDismiss.swift
//  Zapp
//

import SwiftUI
import UIKit

extension View {
    /// Tap anywhere to dismiss the keyboard; a `.decimalPad` has no Return key of its own.
    /// `simultaneousGesture`, not `onTapGesture`, which would swallow taps meant for the
    /// controls underneath.
    func zappDismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}
