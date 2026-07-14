//
//  ZappComponentGallery.swift
//  Zapp
//

import SwiftUI

/// Living reference for the Zapp component set, mirroring `component/zapp/` on Android.
struct ZappComponentGallery: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var isToggleOn = true
    @State private var selectedPeriod = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                ZappScreenHeader(title: "Components", subtitle: "Zapp design system") {
                    ZappStatusChip(text: "Online", variant: .success, dotColor: .success)
                }

                section("FAB + CHIPS") {
                    HStack(spacing: Design.Spacing._lg) {
                        ZappFab(icon: Asset.Assets.Icons.plus.image, contentDescription: "New") { }

                        VStack(alignment: .leading, spacing: Design.Spacing._sm) {
                            ZappStatusChip(text: "Muted")
                            ZappStatusChip(text: "Pending", variant: .accent)
                            ZappStatusChip(text: "Failed", variant: .danger)
                        }
                    }
                }

                section("TOGGLE") {
                    HStack(spacing: Design.Spacing._lg) {
                        ZappToggle(isOn: isToggleOn) { isToggleOn.toggle() }
                        ZappToggle(isOn: !isToggleOn) { isToggleOn.toggle() }

                        Text(isToggleOn ? "On / Off" : "Off / On")
                            .zappFont(.body, style: ZappColors.textMuted)
                    }
                }

                section("ROWS") {
                    VStack(spacing: 0) {
                        ZappRow(
                            title: "Chat profile",
                            subtitle: "Display name, avatar",
                            icon: Asset.Assets.Icons.user.image
                        ) { }
                        ZappRowDivider(inset: true)
                        ZappSelectionRow(title: "Local currency", subtitle: "USD", isSelected: true) { }
                        ZappRowDivider()
                        ZappSelectionRow(
                            title: "Unavailable",
                            subtitle: "Needs a wallet",
                            isSelected: false,
                            isEnabled: false
                        ) { }
                    }
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay(
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    )
                }

                section("BUTTONS (52pt)") {
                    VStack(spacing: Design.Spacing._lg) {
                        ZappButton(title: "Primary") { }
                        ZappButton(title: "Primary disabled", isEnabled: false) { }
                        ZappButton(title: "Ghost", variant: .ghost) { }
                    }
                }

                section("BOTTOM ACTION BAR") {
                    VStack(spacing: Design.Spacing._md) {
                        ZappBottomActionBar(onBack: { })

                        ZappBottomActionBar(onBack: { }) {
                            ZappButton(title: "Continue") { }
                                .frame(width: 150)
                        }
                    }
                }

                section("ACTION TILES (96pt)") {
                    HStack(spacing: Design.Spacing._md) {
                        ZappActionTile(label: "Receive", icon: Asset.Assets.Icons.arrowDown.image) { }
                        ZappActionTile(label: "Send", icon: Asset.Assets.Icons.arrowUp.image) { }
                        ZappActionTile(
                            label: "Swap",
                            icon: Asset.Assets.Icons.swapArrows.image,
                            isEnabled: false
                        ) { }
                    }
                }

                section("SEGMENTED SELECTOR") {
                    ZappSegmentedSelector(
                        options: ["1D", "1W", "1M", "1Y"],
                        selectedIndex: selectedPeriod
                    ) { selectedPeriod = $0 }
                }

            }
            .padding(.horizontal, Design.Spacing._lg)
            .padding(.bottom, 120)
        }
        .background(ZappColors.bg.color(colorScheme))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            ZappSectionLabel(text: title)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZappComponentGallery()
        .onAppear { FontFamily.registerAllCustomFonts() }
}
