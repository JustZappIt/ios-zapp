//
//  SwapAndPaySheets.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-05-26.
//
//  The asset-list loading/empty/failure compositions moved into `ZappSwapAssetPickerSheet`
//  (`SwapSheetViews.swift`) together with the picker itself, so the unified send form and the
//  swap/cross-pay form share one asset picker.
//

import UIKit
import SwiftUI
import ComposableArchitecture

struct FocusableTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var placeholder: String = ""
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor(ZappColors.textMuted.color(colorScheme)),
                .font: FontFamily.Inter.medium.font(size: 16)
            ]
        )
        textField.textAlignment = .center
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.keyboardType = .decimalPad
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.font = FontFamily.Inter.medium.font(size: 16)
        textField.textColor = UIColor(ZappColors.text.color(colorScheme))

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text

        if isFirstResponder && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFirstResponder: $isFirstResponder)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFirstResponder: Bool

        init(text: Binding<String>, isFirstResponder: Binding<Bool>) {
            _text = text
            _isFirstResponder = isFirstResponder
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFirstResponder = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFirstResponder = false
        }
    }
}
