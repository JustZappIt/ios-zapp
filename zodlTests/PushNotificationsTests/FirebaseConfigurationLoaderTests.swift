//
//  FirebaseConfigurationLoaderTests.swift
//  zodlTests
//

import Testing
@testable import zodl_internal

@Suite struct FirebaseConfigurationLoaderTests {
    @Test func missingFirebaseConfigurationDisablesPushWithoutCrashing() {
        #expect(FirebaseConfigurationLoader.load(path: nil, expectedBundleId: "xyz.justzappit.zapp") == nil)
        #expect(FirebaseConfigurationLoader.load(path: "/missing/config.plist", expectedBundleId: nil) == nil)
    }
}
