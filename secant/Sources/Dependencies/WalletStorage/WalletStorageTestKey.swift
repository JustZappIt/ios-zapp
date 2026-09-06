//
//  WalletStorageTestKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 14.11.2022.
//

import ComposableArchitecture
import Foundation
import XCTestDynamicOverlay

extension WalletStorageClient {
    static let noOp = Self(
        importWallet: { _, _, _, _ in },
        exportWallet: { .placeholder },
        areKeysPresent: { false },
        updateBirthday: { _ in },
        markUserPassedPhraseBackupTest: { _ in },
        resetZashi: { },
        importAddressBookEncryptionKeys: { _ in },
        exportAddressBookEncryptionKeys: { .empty },
        importUserMetadataEncryptionKeys: { _, _ in },
        exportUserMetadataEncryptionKeys: { _ in .empty },
        clearEncryptionKeys: { _ in },
        importWalletBackupReminder: { _ in },
        exportWalletBackupReminder: { nil },
        importShieldingReminder: { _, _ in },
        exportShieldingReminder: { _ in nil },
        resetShieldingReminder: { _ in },
        importWalletBackupAcknowledged: { _ in },
        exportWalletBackupAcknowledged: { false },
        importShieldingAcknowledged: { _ in },
        exportShieldingAcknowledged: { false },
        importTorSetupFlag: { _ in },
        exportTorSetupFlag: { false },
        importIronwoodAnnouncementFlag: { _ in },
        // Keep Root's one-time announcement gate closed in tests that use
        // `.noOp`; individual gate tests override this to exercise the
        // unacknowledged path explicitly.
        exportIronwoodAnnouncementFlag: { true },
        importPINHash: { _ in },
        exportPINHash: { nil },
        removePINHash: { },
        importVotingHotkey: { _, _ in },
        exportVotingHotkey: { _ in .init(storedSecret: .init(Data()), version: 0) },
        importGiftCards: { _ in },
        exportGiftCards: { [] },
        importReceivedGifts: { _ in },
        exportReceivedGifts: { [] }
    )
}
