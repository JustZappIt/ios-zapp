// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture

extension Root.Action: CustomDumpReflectable {
    var customDumpMirror: Mirror {
        switch self {
        case .groupInviteReceived:
            return Mirror(reflecting: "Root.Action.groupInviteReceived(<redacted>)")
        default:
            return Mirror(reflecting: self)
        }
    }
}

extension Root.DestinationAction: CustomDumpReflectable {
    var customDumpMirror: Mirror {
        switch self {
        // The URL already contains the secret before routing classifies it. Redact every
        // deeplink so malformed invites and appended tracking text cannot escape this boundary.
        case .deeplink, .deeplinkFailed:
            return Mirror(reflecting: "Root.DestinationAction.deeplink(<redacted>)")
        default:
            return Mirror(reflecting: self)
        }
    }
}
