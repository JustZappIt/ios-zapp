//
//  ChatUsernameEntryView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ChatUsernameEntryView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatUsernameEntry>

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                Text(String(localizable: .chatIdentityTitle))
                    .zappFont(.display, style: ZappColors.text)

                Text(String(localizable: .chatIdentitySubtitle))
                    .zappFont(.body, style: ZappColors.textMuted)

                TextField(
                    String(localizable: .chatIdentityPlaceholder),
                    text: Binding(
                        get: { store.displayName },
                        set: { store.send(.displayNameChanged($0)) }
                    )
                )
                .zappFont(.body, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(Design.Spacing._md)
                .background(ZappColors.surfaceInput.color(colorScheme))

                Text(String(localizable: .chatIdentityRules))
                    .zappFont(.caption, style: ZappColors.textSubtle)

                Spacer()

                ZappButton(
                    title: String(localizable: .chatIdentityContinue),
                    isEnabled: store.isValid
                ) {
                    store.send(.continueTapped)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Design.Spacing._lg)
            .padding(.top, Design.Spacing._2xl)
            .padding(.bottom, Design.Spacing._lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden()
        }
    }
}
