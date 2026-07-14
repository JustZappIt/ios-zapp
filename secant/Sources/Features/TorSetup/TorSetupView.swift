//
//  TorSetupView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-07-10.
//

import SwiftUI
import ComposableArchitecture

struct TorSetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Perception.Bindable var store: StoreOf<TorSetup>
    
    init(store: StoreOf<TorSetup>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            if store.isSettingsView {
                settingsScreen
            } else {
                learnMoreScreen
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    private var settingsScreen: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: String(localizable: .settingsPrivate))

            ScrollView {
                VStack(spacing: 0) {
                    Asset.Assets.Partners.torLogo.image
                        .zImage(width: 36, height: 24, color: .white)
                        .frame(width: 64, height: 64)
                        .background(ZappColors.text.color(colorScheme))
                        .padding(.bottom, Design.Spacing._lg)

                    Text(localizable: .torSetupSettingsDesc1)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Design.Spacing._3xl)

                    ZappSectionLabel(text: String(localizable: .settingsPrivate))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZappToggleRow(
                        title: String(localizable: .smartBannerContentTorTitle),
                        subtitle: String(localizable: .torSetupEnableDesc),
                        icon: Asset.Assets.Icons.shieldZap.image,
                        iconTint: .accentText,
                        iconBackground: .accentSoft,
                        isOn: store.currentSettingsOption == .optIn,
                        action: toggleTorSelection
                    )
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay(
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    )
                }
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.top, Design.Spacing._2xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .zashiBack(
            primaryAction: {
                ZappButton(
                    title: String(localizable: .currencyConversionSaveBtn),
                    isEnabled: !store.isSaveButtonDisabled
                ) {
                    store.send(.saveChangesTapped)
                }
            },
            customDismiss: { store.send(.backToHomeTapped) }
        )
    }

    private var learnMoreScreen: some View {
        VStack {
            ScrollView { learnMoreLayout() }
                .padding(.vertical, 1)

            Spacer()
            learnMoreFooter()
        }
        .navigationBarTitleDisplayMode(.inline)
        .applyScreenBackground()
        .zashiBack(customDismiss: { store.send(.backToHomeTapped) })
    }

    private func toggleTorSelection() {
        store.send(.settingsOptionTapped(store.currentSettingsOption == .optIn ? .optOut : .optIn))
    }
    
    private func learnMoreLayout() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(desc1: String(localizable: .torSetupLearnDesc), desc2: "")

            ForEach(TorSetup.State.LearnMoreOptions.allCases, id: \.self) { option in
                HStack(alignment: .top, spacing: 0) {
                    optionIcon(option.icon().image)
                    optionVStack(option.title(), subtitle: option.subtitle())
                }
                .padding(.top, 20)
            }
            .padding(.bottom, 12)
        }
        .screenHorizontalPadding()
    }
 
    private func learnMoreFooter() -> some View {
        VStack {
            ZashiButton(
                String(localizable: .torSetupLearnBtnOut),
                type: .ghost
            ) {
                store.send(.disableTapped)
            }
            
            ZashiButton(String(localizable: .torSetupLearnBtnIn)) {
                store.send(.enableTapped)
            }
            .padding(.bottom, 24)
        }
        .screenHorizontalPadding()
    }
}

// MARK: - UI components

extension TorSetupView {
    private func icons() -> some View {
        RoundedRectangle(cornerRadius: Design.Radius._full)
            .fill(Color(red: 0.2, green: 0.23, blue: 0.25))
            .frame(width: 64, height: 64)
            .overlay {
                Asset.Assets.Partners.torLogo.image
                    .zImage(width: 36, height: 24, color: .white)
            }
            .padding(.top, 24)
    }
    
    private func title() -> some View {
        Text(
            store.isSettingsView
            ? String(localizable: .settingsPrivate)
            : String(localizable: .torSetupTitle)
        )
        .zFont(.semiBold, size: 24, style: Design.Text.primary)
    }
    
    private func note() -> some View {
        HStack(alignment: .top, spacing: 0) {
            Asset.Assets.infoCircle.image
                .zImage(size: 20, style: Design.Text.primary)
                .padding(.trailing, 12)

            Text(localizable: .currencyConversionNote)
                .zFont(size: 12, style: Design.Text.tertiary)
        }
        .screenHorizontalPadding()
    }
    
    private func optionVStack(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .zFont(.semiBold, size: 14, style: Design.Text.primary)

            Text(subtitle)
                .zFont(size: 14, style: Design.Text.tertiary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .padding(.trailing, 16)
    }
    
    private func optionIcon(_ icon: Image) -> some View {
        icon
            .zImage(size: 20, style: Design.Text.primary)
            .padding(10)
            .background {
                Circle()
                    .fill(Design.Surfaces.bgTertiary.color(colorScheme))
            }
            .padding(.trailing, 16)
    }
    
    private func header(desc1: String, desc2: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                icons()
                    .padding(.bottom, 24)
                    .padding(.top, 12)

                Spacer()
            }
            
            title()
                .padding(.bottom, 8)
            
            Text(desc1)
                .zFont(size: 14, style: Design.Text.tertiary)
                .padding(.bottom, store.isSettingsView ? 16 : 12)

            if store.isSettingsView {
                Text(desc2)
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationView {
        TorSetupView(store: TorSetup.initial)
    }
}

// MARK: - Store

extension TorSetup {
    @MainActor static var initial = StoreOf<TorSetup>(
        initialState: .init(isSettingsView: false)
    ) {
        TorSetup()
    }
}

// MARK: - Placeholders

extension TorSetup.State {
    static var initial: TorSetup.State { TorSetup.State() }
}
