//
//  ZappMessagingBuildConfig.swift
//  Zapp
//
//  Worklet startup values that Android sources from BuildConfig via
//  gradle.properties. iOS has no xcconfig and no BuildConfig analogue, so they
//  live here.
//
//  Every value here is PUBLIC by design — a blind peer's public key, its
//  bootstrap address and its mailbox endpoint are advertised to anyone who wants
//  to relay through it, and zodl-android commits them to gradle.properties for
//  the same reason. Nothing here is a secret.
//
//  Keep them in step with zodl-android's gradle.properties. If they drift, the
//  failure is silent: no offline delivery, a DHT with no seed nodes, or — for the
//  mailbox URL, which doubles as the allow-list for host-carried requests — every
//  invite POST rejected before it leaves the device.
//

import Foundation
import ZappMessaging

enum ZappMessagingBuildConfig {
    /// Blind peer that stores messages for us while we are offline. Without it,
    /// messages only ever arrive when both peers happen to be online at once.
    static let blindPeerKeys = "5ccrwsgqfg1hawwcbckmisww4sy3qns5scsntxfztgx7pt4eps5o"

    /// DHT seed node. Without it the swarm has nothing to join through.
    static let bootstrapNodes = "140.245.193.100:49737"

    /// Stable public address for an immediate blind-peer connection attempt.
    /// HyperDHT retains normal DHT lookup as the fallback path.
    static let blindPeerAddress = "140.245.193.100:49737"

    /// Bootstrap invite mailbox over HTTPS, for the networks that drop HyperDHT's
    /// UDP altogether — the only path that reaches a firewalled peer there. The
    /// worklet names the destination and the SDK checks it against this value
    /// before POSTing, so it is also the allow-list: get it wrong and the feature
    /// does not misbehave, it silently stops existing.
    static let inviteMailboxURL = "https://ntfy.140.245.193.100.sslip.io/zapp-invite"

    /// Must stay nil/`info` in anything shipped: `debug` dumps keypairs and
    /// verbose stream lifecycle into the log.
    static let logLevel: String? = {
        #if DEBUG
        return "info"
        #else
        return nil
        #endif
    }()

    /// `localGateway` is deliberately absent: Android reads the default-route
    /// gateway from ConnectivityManager, and iOS has no public API for the route
    /// table. The flag is optional and the DHT degrades gracefully without it —
    /// it only costs us the hotspot relay path.
    static func config() throws -> ZappMessagingConfig {
        ZappMessagingConfig(
            dataDir: try ZappMessagingConfig.defaultDataDir(),
            blindPeerKeys: blindPeerKeys,
            bootstrapNodes: bootstrapNodes,
            blindPeerAddress: blindPeerAddress,
            inviteMailboxURL: inviteMailboxURL,
            logLevel: logLevel,
            mediaMaxBytes: 16 * 1024 * 1024
        )
    }
}
