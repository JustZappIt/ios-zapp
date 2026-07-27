//
//  ScreenCaptureTestKey.swift
//  Zapp
//

import ComposableArchitecture

extension ScreenCaptureClient: TestDependencyKey {
    /// "Nothing is recording" is the state every existing reveal test was written against, and
    /// the macro's unimplemented default would fail all of them for asking a question they do not
    /// care about. A test that exercises the refusal overrides `isCaptured` explicitly.
    static let testValue = Self(isCaptured: { false })
}
