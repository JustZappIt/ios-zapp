//
//  KlipyGIFTestKey.swift
//  Zapp
//

import ComposableArchitecture

extension KlipyGIFClient: TestDependencyKey {
    /// Unimplemented apart from `isConfigured`, so a test that reaches Klipy without saying so
    /// fails rather than quietly seeing an empty grid.
    static let testValue = KlipyGIFClient()
}
