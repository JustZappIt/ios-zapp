//
//  AnnotationSheet.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-01-27.
//

import SwiftUI
import ComposableArchitecture

extension TransactionDetailsView {
    @ViewBuilder func annotationContent(_ isEditMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditMode
                 ? String(localizable: .annotationEdit)
                 : String(localizable: .annotationAddArticle)
            )
            .zappFont(.sectionTitle, style: ZappColors.text)
            .padding(.top, 32)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $store.annotationToInput)
                    .focused($isAnnotationFocused)
                    .zappFont(.body, style: ZappColors.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 122)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ZappColors.surfaceInput.color(colorScheme))
                    .overlay {
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if store.annotationToInput.isEmpty {
                            Text(localizable: .annotationPlaceholder)
                                .zappFont(.body, style: ZappColors.textSubtle)
                                .allowsHitTesting(false)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 16)
                        }
                    }

                Text(localizable: .annotationChars(String(store.annotationToInput.count), String(TransactionDetails.State.Constants.annotationMaxLength)))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }
            .padding(.bottom, 32)

            if isEditMode {
                HStack(spacing: 12) {
                    ZappButton(
                        title: String(localizable: .annotationDelete),
                        variant: .danger
                    ) {
                        store.send(.deleteNoteTapped)
                    }

                    ZappButton(
                        title: String(localizable: .annotationSave),
                        isEnabled: store.isAnnotationModified
                    ) {
                        store.send(.saveNoteTapped)
                    }
                }
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            } else {
                ZappButton(
                    title: String(localizable: .annotationAdd),
                    isEnabled: !store.annotationToInput.isEmpty
                ) {
                    store.send(.addNoteTapped)
                }
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
        }
    }
}
