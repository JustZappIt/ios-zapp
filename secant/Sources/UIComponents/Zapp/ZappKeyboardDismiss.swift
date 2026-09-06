//
//  ZappKeyboardDismiss.swift
//  Zapp
//

import SwiftUI
import UIKit

extension View {
    /// Tap anywhere to put the keyboard away — the behaviour iOS users expect from any screen
    /// whose only field is a number pad, since a `.decimalPad` carries no Return key to dismiss
    /// itself with.
    ///
    /// `simultaneousGesture` rather than `onTapGesture`: the latter would swallow taps meant for
    /// the buttons and rows underneath. Simultaneous recognition lets the tap do both, which is
    /// also what you want — tapping a control while editing should commit the edit and act.
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
