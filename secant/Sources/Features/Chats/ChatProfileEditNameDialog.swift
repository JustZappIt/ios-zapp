//
//  ChatProfileEditNameDialog.swift
//  Zapp
//
//  Android's `ChatProfileEditNameDialog`.
//

import SwiftUI

struct ChatProfileEditNameDialog: View {
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isFieldFocused: Bool

    let editName: ChatProfile.State.EditName
    let onChange: (String) -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        // No scrim dismissal while a save is in flight, matching Android's guard: dropping the
        // dialog under an unresolved write leaves nothing to report its outcome to.
        ZappDialog(onScrimTap: editName.isSaving ? nil : onDismiss) {
            Text(String(localizable: .chatProfileEditDisplayName))
                .zappFont(.sectionTitle, style: ZappColors.text)

            TextField(
                String(localizable: .chatProfileDisplayName),
                text: Binding(get: { editName.draft }, set: onChange)
            )
            .focused($isFieldFocused)
            .zappFont(.body, style: ZappColors.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(onSave)
            .disabled(editName.isSaving)
            .padding(Design.Spacing._lg)
            .background(ZappColors.surfaceInput.color(colorScheme))

            Text(String(localizable: .chatProfileDisplayNameHint))
                .zappFont(.caption, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if editName.failed {
                Text(String(localizable: .chatProfileSaveFailed))
                    .zappFont(.caption, style: ZappColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Design.Spacing._lg) {
                ZappButton(
                    title: String(localizable: .generalCancel),
                    variant: .ghost,
                    isEnabled: !editName.isSaving,
                    action: onDismiss
                )

                ZappButton(
                    title: editName.isSaving
                        ? String(localizable: .chatProfileSaving)
                        : String(localizable: .chatProfileSave),
                    isEnabled: editName.canSave,
                    action: onSave
                )
            }
        }
        .onAppear { isFieldFocused = true }
    }
}

#Preview {
    Color.gray
        .overlay {
            ChatProfileEditNameDialog(
                editName: ChatProfile.State.EditName(draft: "chinmay"),
                onChange: { _ in },
                onSave: { },
                onDismiss: { }
            )
        }
}
