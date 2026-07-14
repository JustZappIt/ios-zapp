//
//  ServerSetupView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2024-02-07.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct ServerSetupView: View {
    @Environment(\.colorScheme) var colorScheme

    var customDismiss: (() -> Void)? = nil

    @Perception.Bindable var store: StoreOf<ServerSetup>

    init(store: StoreOf<ServerSetup>, customDismiss: (() -> Void)? = nil) {
        self.store = store
        self.customDismiss = customDismiss
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .serverSetupTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        if store.topKServers.isEmpty && store.isEvaluatingServers {
                            VStack(spacing: Design.Spacing._md) {
                                ProgressView()
                                Text(localizable: .serverSetupPerformingTest)
                                    .zappFont(.body, style: ZappColors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Design.Spacing._3xl)
                        }

                        if !store.topKServers.isEmpty {
                            serverGroupHeader(
                                String(localizable: .serverSetupFastestServers),
                                showsRefresh: true
                            )
                            zappServerGroup(store.topKServers)
                        }

                        serverGroupHeader(
                            store.topKServers.isEmpty
                                ? String(localizable: .serverSetupAllServers)
                                : String(localizable: .serverSetupOtherServers)
                        )
                        zappServerGroup(store.servers)

                        HStack(alignment: .top, spacing: Design.Spacing._md) {
                            Asset.Assets.infoOutline.image
                                .zImage(width: 18, height: 18, style: ZappColors.textMuted)

                            Text(localizable: .serverSetupMultiServerInfo)
                                .zappFont(.caption, style: ZappColors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, Design.Spacing._2xl)
                        .padding(.vertical, Design.Spacing._xl)
                    }
                }
                .disabled(store.isUpdatingServer)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                store.isUpdatingServer,
                primaryAction: {
                    ZappButton(
                        title: String(localizable: .serverSetupSave),
                        isEnabled: store.canSave && !store.isUpdatingServer
                    ) {
                        store.send(.setServerTapped)
                    }
                },
                customDismiss: customDismiss
            )
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    private func serverGroupHeader(_ title: String, showsRefresh: Bool = false) -> some View {
        HStack(spacing: Design.Spacing._md) {
            ZappSectionLabel(text: title)

            Spacer()

            if showsRefresh {
                Button {
                    store.send(.refreshServersTapped)
                } label: {
                    HStack(spacing: Design.Spacing._xs) {
                        Text(localizable: .serverSetupRefresh)
                            .zappFont(.buttonSmall, style: ZappColors.text)

                        if store.isEvaluatingServers {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Asset.Assets.refreshCCW2.image
                                .zImage(width: 18, height: 18, style: ZappColors.text)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.zappPress)
                .disabled(store.isEvaluatingServers || store.isUpdatingServer)
            }
        }
        .padding(.horizontal, Design.Spacing._2xl)
        .padding(.top, Design.Spacing._lg)
    }

    private func zappServerGroup(_ servers: [ZcashSDKEnvironment.Server]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(servers.enumerated()), id: \.element) { index, server in
                let value = server.value(for: store.network)
                let customLabel = String(localizable: .serverSetupCustom)
                let isCustom = value == customLabel
                let isSelected = store.selectedServer == value

                ZappSelectionRow(
                    title: value,
                    subtitle: serverSubtitle(server, value: value),
                    isSelected: isSelected
                ) {
                    store.send(.connectionModeChanged(.manual))
                    store.send(.serverSelected(value))
                }

                if isCustom && isSelected {
                    TextField(
                        String(localizable: .serverSetupPlaceholder),
                        text: $store.customServer
                    )
                    .zappFont(.mono, style: ZappColors.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(Design.Spacing._md)
                    .background(ZappColors.surfaceInput.color(colorScheme))
                    .overlay(
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    )
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.bottom, Design.Spacing._md)
                }

                if index != servers.count - 1 {
                    ZappRowDivider(inset: true)
                }
            }
        }
        .background(ZappColors.surface.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, Design.Spacing._sm)
    }

    private func serverSubtitle(_ server: ZcashSDKEnvironment.Server, value: String) -> String? {
        let description = server.desc(for: store.network)
        guard value == store.activeSyncServer else { return description }
        return [description, String(localizable: .serverSetupActive)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

}

// MARK: - Previews

#Preview {
    NavigationView {
        ServerSetupView(store: ServerSetup.placeholder)
    }
}

// MARK: Placeholders

extension ServerSetup {
    @MainActor static let placeholder = StoreOf<ServerSetup>(
        initialState: .initial
    ) {
        ServerSetup()
    }
}
