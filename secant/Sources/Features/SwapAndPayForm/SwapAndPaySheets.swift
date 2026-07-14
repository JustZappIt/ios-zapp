//
//  SwapAndPaySheets.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-05-26.
//

import UIKit
import SwiftUI
import ComposableArchitecture

extension SwapAndPayForm {
    @ViewBuilder func assetsLoadingComposition(_ colorScheme: ColorScheme) -> some View {
        List {
            WithPerceptionTracking {
                ForEach(0..<15) { _ in
                    NoTransactionPlaceholder(true)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(ZappColors.bg.color(colorScheme))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .disabled(true)
        .background(ZappColors.bg.color(colorScheme))
        .listStyle(.plain)
    }

    @ViewBuilder func assetsEmptyComposition(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            placeholderBackdrop(colorScheme) {
                VStack(spacing: 0) {
                    Asset.Assets.Illustrations.emptyState.image
                        .resizable()
                        .frame(width: 164, height: 164)
                        .padding(.bottom, Design.Spacing._2xl)

                    Text(localizable: .swapAndPayEmptyAssetsTitle)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .padding(.bottom, Design.Spacing._md)

                    Text(localizable: .swapAndPayEmptyAssetsSubtitle)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Design.Spacing._5xl)
            }
        }
    }

    @ViewBuilder func assetsFailureComposition(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            placeholderBackdrop(colorScheme) {
                VStack(alignment: .center, spacing: 0) {
                    Asset.Assets.Illustrations.cone.image
                        .zImage(width: 164, height: 164, style: ZappColors.text)
                        .padding(.bottom, Design.Spacing._2xl)

                    Text(localizable: .swapAndPayFailureWrong)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .padding(.bottom, Design.Spacing._md)

                    Text(localizable: .swapAndPayFailureWrongDesc)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Design.Spacing._2xl)
                        .padding(.bottom, Design.Spacing._2xl)

                    if let retryFailure = store.swapAssetFailedWithRetry, retryFailure {
                        ZappButton(
                            title: String(localizable: .swapAndPayFailureTryAgain),
                            variant: .secondary
                        ) {
                            store.send(.trySwapsAssetsAgainTapped)
                        }
                        .padding(.horizontal, Design.Spacing._6xl)
                    }
                }
            }
        }
    }

    @ViewBuilder private func placeholderBackdrop<Content: View>(
        _ colorScheme: ColorScheme,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<5) { _ in
                    NoTransactionPlaceholder()
                }

                Spacer()
            }
            .overlay {
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .clear, location: 0.0),
                        Gradient.Stop(color: ZappColors.bg.color(colorScheme), location: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            content()
        }
    }
}

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
