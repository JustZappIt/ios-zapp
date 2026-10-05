//
//  ZappFittedSheetDetent.swift
//  Zapp
//
//  Sizes a scrolling sheet to its content, as Android's wrap-content bottom sheets are. A fixed
//  `.height` detent left an empty band below shorter content; `zashiSheet` can't measure a sheet
//  whose content sits in a `ScrollView`, because the scroll view takes whatever height it's given.
//  So the sheet measures the content inside its scroll view and reports it here. `.large` stays
//  available for larger type, where the content scrolls.
//

import SwiftUI

private struct ZappFittedSheetDetent: ViewModifier {
    let contentHeight: CGFloat

    @State private var selection: PresentationDetent

    init(contentHeight: CGFloat) {
        self.contentHeight = contentHeight
        _selection = State(initialValue: .height(contentHeight))
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents([.height(contentHeight), .large], selection: $selection)
            .onChange(of: contentHeight) { height in
                // Follow the content unless the user pulled the sheet up to full height.
                if selection != .large {
                    selection = .height(height)
                }
            }
    }
}

extension View {
    /// Presents this sheet at `contentHeight`, the measured height of its content, with `.large`
    /// kept for larger type. Pass a sensible estimate until the first measurement arrives.
    func zappFittedSheetDetent(_ contentHeight: CGFloat) -> some View {
        modifier(ZappFittedSheetDetent(contentHeight: contentHeight))
    }
}
