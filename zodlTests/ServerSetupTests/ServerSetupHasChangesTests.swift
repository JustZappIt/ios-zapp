//
//  ServerSetupHasChangesTests.swift
//  zodlTests
//
//  More tests — server. Covers ServerSetup.State.hasChanges / automaticDisplayServer
//  (Features/ServerSetup/ServerSetupStore.swift). Complements ServerSetupStoreTests.
//

import Testing
@testable import zodl_internal

@Suite struct ServerSetupHasChangesTests {
    @Test func hasChangesDetectsModeChange() {
        var state = ServerSetup.State(connectionMode: .automatic)
        #expect(!state.hasChanges)
        state.connectionMode = .manual
        #expect(state.hasChanges)
    }

    @Test func hasChangesDetectsServerChange() {
        var state = ServerSetup.State(connectionMode: .manual, selectedServer: nil)
        #expect(!state.hasChanges)
        state.selectedServer = "some.server:443"
        #expect(state.hasChanges)
    }

    @Test func hasChangesDetectsCustomServerEdit() {
        let customLabel = String(localizable: .serverSetupCustom)
        var state = ServerSetup.State(connectionMode: .manual, selectedServer: customLabel)
        state.initialSelectedServer = customLabel // keep serverChanged false
        #expect(!state.hasChanges)
        state.customServer = "custom.server:443" // differs from initialCustomServer ("")
        #expect(state.hasChanges)
    }

    @Test func automaticDisplayServerFallsBackToActiveSyncServer() {
        var state = ServerSetup.State() // no benchmarked servers yet
        state.activeSyncServer = "active.server:443"
        #expect(state.recommendedSyncServer == nil)
        #expect(state.automaticDisplayServer == "active.server:443")
    }

    @Test func canSaveRequiresAChange() {
        let state = ServerSetup.State(connectionMode: .automatic)
        #expect(!state.canSave)
    }

    @Test func canSaveAcceptsAutomaticModeChange() {
        var state = ServerSetup.State(connectionMode: .manual)
        state.connectionMode = .automatic
        #expect(state.canSave)
    }

    @Test func canSaveRequiresManualSelection() {
        var state = ServerSetup.State(connectionMode: .automatic)
        state.connectionMode = .manual
        #expect(!state.canSave)
    }

    @Test func canSaveRejectsInvalidCustomEndpoint() {
        let customLabel = String(localizable: .serverSetupCustom)
        var state = ServerSetup.State(connectionMode: .manual, selectedServer: customLabel)
        state.initialSelectedServer = customLabel
        state.customServer = "not an endpoint"
        #expect(!state.canSave)
    }

    @Test func canSaveAcceptsValidCustomEndpoint() {
        let customLabel = String(localizable: .serverSetupCustom)
        var state = ServerSetup.State(connectionMode: .manual, selectedServer: customLabel)
        state.initialSelectedServer = customLabel
        state.customServer = "custom.server:443"
        #expect(state.canSave)
    }
}
