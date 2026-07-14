//
//  ZappSectionLabel.swift
//  Zapp
//

import SwiftUI

struct ZappSectionLabel: View {
    let text: String
    var color: ZappColors = .textMuted

    var body: some View {
        Text(text.uppercased())
            .zappFont(.groupLabel, style: color)
    }
}

/// Uppercase group header for a card-stacked settings section.
struct ZappGroupHeader: View {
    let text: String

    var body: some View {
        ZappSectionLabel(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ZappGroupHeader(text: "Security")
        ZappSectionLabel(text: "Accent", color: .accentText)
    }
    .applyScreenBackground()
}
