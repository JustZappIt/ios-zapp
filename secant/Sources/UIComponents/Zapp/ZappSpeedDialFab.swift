//
//  ZappSpeedDialFab.swift
//  Zapp
//
//  Zapp fork: iOS port of android-zapp's `ZappSpeedDialFab`. Collapsed it is a
//  single accent FAB; tapping rotates the plus into a cross and reveals labelled
//  actions above it over a tap-to-dismiss scrim. Selecting an action collapses
//  first, then fires its handler.
//

import SwiftUI

struct ZappSpeedDialAction: Identifiable {
    let id: String
    let icon: Image
    let label: String
    let onTap: () -> Void

    init(id: String, icon: Image, label: String, onTap: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.label = label
        self.onTap = onTap
    }
}

struct ZappSpeedDialFab: View {
    @Environment(\.colorScheme) private var colorScheme

    let actions: [ZappSpeedDialAction]
    var bottomPadding: CGFloat = ZappNavBar.fabBottomPadding

    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if expanded {
                ZappColor.overlay(colorScheme)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: ZappMotion.content)) {
                            expanded = false
                        }
                    }
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: 12) {
                if expanded {
                    ForEach(actions) { action in
                        actionRow(action)
                    }
                    .transition(
                        .opacity.combined(with: .move(edge: .bottom))
                    )
                }

                toggleFab()
            }
            .padding(.trailing, 18)
            .padding(.bottom, bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.easeInOut(duration: ZappMotion.content), value: expanded)
    }

    @ViewBuilder private func actionRow(_ action: ZappSpeedDialAction) -> some View {
        HStack(spacing: 12) {
            Text(action.label)
                .font(.custom(FontFamily.Inter.black.name, size: 14))
                .foregroundColor(ZappColor.text(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ZappColor.surface(colorScheme))
                .overlay {
                    Rectangle()
                        .stroke(ZappColor.border(colorScheme), lineWidth: 1)
                }

            ZappFab(
                icon: action.icon,
                accessibilityLabel: action.label
            ) {
                withAnimation(.easeInOut(duration: ZappMotion.content)) {
                    expanded = false
                }
                action.onTap()
            }
        }
    }

    @ViewBuilder private func toggleFab() -> some View {
        Button {
            withAnimation(.easeInOut(duration: ZappMotion.content)) {
                expanded.toggle()
            }
        } label: {
            ZStack {
                Rectangle()
                    .fill(ZappColor.accent(colorScheme))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Rectangle()
                            .stroke(ZappColor.border(colorScheme), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)

                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(ZappColor.onAccent(colorScheme))
                    .rotationEffect(.degrees(expanded ? 45 : 0))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(
            expanded
            ? String(localizable: .zappFabCollapse)
            : String(localizable: .zappFabExpand)
        )
    }
}
