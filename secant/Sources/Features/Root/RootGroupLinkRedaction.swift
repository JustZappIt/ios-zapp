// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture

extension Root.Action: CustomDumpReflectable {
    var customDumpMirror: Mirror {
        switch self {
        case .groupInviteReceived:
            // Keep an enum mirror with redacted children. A String's leaf mirror makes
            // CustomDump fall back to describing the original action, exposing the URL.
            return Mirror(self, children: ["groupInviteReceived": "<redacted>"], displayStyle: .enum)
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
        case .deeplink:
            return Mirror(self, children: ["deeplink": "<redacted>"], displayStyle: .enum)
        case .deeplinkFailed:
            return Mirror(self, children: ["deeplinkFailed": "<redacted>"], displayStyle: .enum)
        default:
            return Mirror(reflecting: self)
        }
    }
}
