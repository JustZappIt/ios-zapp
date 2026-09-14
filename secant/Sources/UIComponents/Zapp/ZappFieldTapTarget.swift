//
//  ZappFieldTapTarget.swift
//  Zapp
//

import SwiftUI

extension View {
    /// Hands taps on an input box's padding, border and `minHeight` to the field inside it, which
    /// SwiftUI otherwise hit-tests only at its own one-line frame. Apply to the box, `.focused` to
    /// the field.
    func zappFieldTapTarget(_ isFocused: FocusState<Bool>.Binding) -> some View {
        contentShape(Rectangle())
            .onTapGesture { isFocused.wrappedValue = true }
    }

    /// The `equals:` spelling, for screens tracking several fields in one `@FocusState`.
    func zappFieldTapTarget<Value: Hashable>(
        _ focus: FocusState<Value?>.Binding,
        equals value: Value
    ) -> some View {
        contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = value }
    }
}
