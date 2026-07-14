//
//  RequestZecView.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-20-2024.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct RequestZecView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let brandmarkSize: CGFloat = 64
        static let memoMinHeight: CGFloat = 155
        static let memoMaxHeight: CGFloat = 300
        static let keyboardAccessoryHeight: CGFloat = 38
    }

    @Perception.Bindable var store: StoreOf<RequestZec>

    @State private var keyboardVisible = false

    @FocusState private var isMemoFocused

    let tokenName: String

    init(store: StoreOf<RequestZec>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .generalRequest),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(spacing: 0) {
                        Asset.Assets.Brandmarks.brandmarkMax.image
                            .resizable()
                            .frame(width: Constants.brandmarkSize, height: Constants.brandmarkSize)
                            .padding(.top, Design.Spacing._3xl)

                        PrivacyBadge(store.maxPrivacy ? .max : .low)
                            .padding(.top, Design.Spacing._3xl)

                        Text(localizable: .requestZecTitle)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .padding(.top, Design.Spacing._lg)

                        Group {
                            Text(store.requestedZec.decimalString())
                            + Text(" \(tokenName)")
                                .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                        }
                        .zappFont(.display, style: ZappColors.text)
                        .minimumScaleFactor(0.1)
                        .lineLimit(1)
                        .padding(.top, Design.Spacing._xs)

                        if store.maxPrivacy {
                            MessageEditorView(
                                store: store.memoStore(),
                                title: "",
                                placeholder: String(localizable: .requestZecWhatFor)
                            )
                            .frame(minHeight: Constants.memoMinHeight)
                            .frame(maxHeight: Constants.memoMaxHeight)
                            .focused($isMemoFocused)
                            .padding(.top, Design.Spacing._2xl)
                            .onAppear {
                                store.send(.onAppear)
                                isMemoFocused = true
                            }
                        }
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
                .trackKeyboardVisibility($keyboardVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(primaryAction: {
                ZappButton(
                    title: String(localizable: .generalRequest),
                    isEnabled: store.memoState.isValid
                ) {
                    store.send(.requestTapped)
                }
            })
            .overlay {
                if keyboardVisible {
                    keyboardDismissAccessory
                }
            }
        }
    }

    private var keyboardDismissAccessory: some View {
        VStack(spacing: 0) {
            Spacer()

            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)

            HStack {
                Spacer()

                Button {
                    isMemoFocused = false
                } label: {
                    Text(String(localizable: .generalDone).uppercased())
                        .zappFont(.chip, style: ZappColors.accentText)
                }
                .buttonStyle(.zappPress)
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(height: Constants.keyboardAccessoryHeight)
            .frame(maxWidth: .infinity)
            .background(ZappColors.surface.color(colorScheme))
        }
    }
}

#Preview {
    NavigationView {
        RequestZecView(store: RequestZec.placeholder, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension RequestZec.State {
    static var initial: RequestZec.State { RequestZec.State() }
}

extension RequestZec {
    @MainActor static let placeholder = StoreOf<RequestZec>(
        initialState: .initial
    ) {
        RequestZec()
    }
}

// MARK: - Store

extension StoreOf<RequestZec> {
    func memoStore() -> StoreOf<MessageEditor> {
        self.scope(
            state: \.memoState,
            action: \.memo
        )
    }
}
