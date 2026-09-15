//
//  PartnerKeys.swift
//  Zashi
//
//  Created by Lukáš Korba on 05-17-2024.
//

import Foundation

struct PartnerKeys {
    // Scripts/validate-partner-keys.sh contains the subset that must be present
    // for archive builds. Keys with safe runtime defaults remain optional.
    private enum Constants {
        static let cbProjectId = "cbProjectId"
        static let flexaPublishableKey = "flexaPublishableKey"
        static let flexaPublishableTestKey = "flexaPublishableTestKey"
        static let nearKey = "nearKey"
        static let cmcKey = "cmcKey"
        static let nearFeeDepositAddress = "nearFeeDepositAddress"
        static let p2pPimlicoApiKey = "p2pPimlicoApiKey"
        static let p2pScreeningApiUrl = "p2pScreeningApiUrl"
        static let p2pScreeningKey = "p2pScreeningKey"
        static let p2pRpcBaseMainnet = "p2pRpcBaseMainnet"
        static let p2pSubgraphMainnet = "p2pSubgraphMainnet"
        static let p2pSubgraphSepolia = "p2pSubgraphSepolia"
        static let p2pSponsorshipPolicyId = "p2pSponsorshipPolicyId"
        static let reclaimAppId = "reclaimAppId"
        static let reclaimAppSecret = "reclaimAppSecret"
        static let livenessApiUrl = "livenessApiUrl"
        static let livenessApiKey = "livenessApiKey"
        static let livenessTenant = "livenessTenant"
        static let klipyKey = "klipyKey"
#if DEBUG
        static let testSeed = "testSeed"
#endif
    }
    
    static var cbProjectId: String? {
        PartnerKeys.value(for: Constants.cbProjectId)
    }
    
    static var flexaPublishableKey: String? {
        PartnerKeys.value(for: Constants.flexaPublishableKey)
    }
    
    static var flexaPublishableTestKey: String? {
        PartnerKeys.value(for: Constants.flexaPublishableTestKey)
    }
    
    static var nearKey: String? {
        PartnerKeys.value(for: Constants.nearKey)
    }
    
    static var cmcKey: String? {
        PartnerKeys.value(for: Constants.cmcKey)
    }
    
    static var nearFeeDepositAddress: String? {
        PartnerKeys.value(for: Constants.nearFeeDepositAddress)
    }

    static var p2pPimlicoApiKey: String? {
        PartnerKeys.value(for: Constants.p2pPimlicoApiKey)
    }

    /// P2P's screening intake and its shared key. Without both, Buy is closed rather than placing
    /// orders that never fill.
    static var p2pScreeningApiUrl: String? {
        PartnerKeys.value(for: Constants.p2pScreeningApiUrl)
    }

    static var p2pScreeningKey: String? {
        PartnerKeys.value(for: Constants.p2pScreeningKey)
    }

    static var isOnrampConfigured: Bool {
        guard let url = p2pScreeningApiUrl, let key = p2pScreeningKey else { return false }
        return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var p2pRpcBaseMainnet: String? {
        PartnerKeys.value(for: Constants.p2pRpcBaseMainnet)
    }

    static var p2pSubgraphMainnet: String? {
        PartnerKeys.value(for: Constants.p2pSubgraphMainnet)
    }

    /// Optional: the framework's Sepolia default currently resolves to a deleted deployment.
    static var p2pSubgraphSepolia: String? {
        PartnerKeys.value(for: Constants.p2pSubgraphSepolia)
    }

    static var p2pSponsorshipPolicyId: String? {
        PartnerKeys.value(for: Constants.p2pSponsorshipPolicyId)
    }

    /// The Reclaim application's own Ethereum address, and its private key. Both ship in the
    /// binary deliberately: an extracted secret cannot forge a proof — Reclaim's attestors sign
    /// those — and cannot farm reputation, because the proof still binds to the smart account that
    /// submits it. Optional on purpose; a build without them is one that cannot verify, not one
    /// that cannot run.
    static var reclaimAppId: String? {
        PartnerKeys.value(for: Constants.reclaimAppId)
    }

    static var reclaimAppSecret: String? {
        PartnerKeys.value(for: Constants.reclaimAppSecret)
    }

    /// Ships in the binary on the Reclaim credentials' reasoning: an extracted key can open a
    /// widget session but cannot mint an attestation. Optional, like them.
    static var livenessApiUrl: String? {
        PartnerKeys.value(for: Constants.livenessApiUrl)
    }

    static var livenessApiKey: String? {
        PartnerKeys.value(for: Constants.livenessApiKey)
    }

    static var livenessTenant: String? {
        PartnerKeys.value(for: Constants.livenessTenant)
    }

    static var klipyKey: String? {
        PartnerKeys.value(for: Constants.klipyKey)
    }

#if DEBUG
    static var testSeed: String? {
        PartnerKeys.value(for: Constants.testSeed)
    }
#endif
}

private extension PartnerKeys {
    static func value(for key: String) -> String? {
        let fileName = "PartnerKeys.plist"

        guard
            let configFile = Bundle.main.url(forResource: fileName, withExtension: nil),
            let properties = NSDictionary(contentsOf: configFile),
            let key = properties[key] as? String
        else {
            return nil
        }

        return key
    }
}
