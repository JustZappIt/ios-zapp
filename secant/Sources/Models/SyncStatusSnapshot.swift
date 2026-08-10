//
//  SyncStatusSnapshot.swift
//  Zashi
//
//  Created by Lukáš Korba on 07.07.2022.
//

import Foundation
@preconcurrency import ZcashLightClientKit

struct SyncStatusSnapshot: Equatable {
    let message: String
    let syncStatus: SyncStatus
    
    init(_ syncStatus: SyncStatus = .unprepared, _ message: String = "") {
        self.message = message
        self.syncStatus = syncStatus
    }
    
    static func snapshotFor(state: SyncStatus) -> SyncStatusSnapshot {
        switch state {
        case .upToDate:
            return SyncStatusSnapshot(state, String(localizable: .syncMessageUptodate))
            
        case .unprepared:
            return SyncStatusSnapshot(state, String(localizable: .syncMessageUnprepared))
            
        case .error(let error):
            let zcashError = error.toZcashError()
            // This is already readable prose and includes the server and support diagnostics, so it
            // should not receive the generic "Error: " prefix or the SDK's raw enum dump.
            if let message = zcashError.incompatibleServerMessage {
                return SyncStatusSnapshot(state, message)
            }
            return SyncStatusSnapshot(state, String(localizable: .syncMessageError(zcashError.detailedMessage)))

        case .stopped:
            return SyncStatusSnapshot(state, String(localizable: .syncMessageStopped))

        case let .syncing(syncProgress, _):
            return SyncStatusSnapshot(state, String(localizable: .syncMessageSync(String(format: "%0.1f", syncProgress * 100))))
        }
    }
}

extension SyncStatusSnapshot {
    static let initial = SyncStatusSnapshot()
    
    static let placeholder = SyncStatusSnapshot(.unprepared, "23% synced")
}
