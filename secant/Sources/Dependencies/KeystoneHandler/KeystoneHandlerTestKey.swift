//
//  KeystoneHandlerTestKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 2024-11-20.
//

import ComposableArchitecture
import IssueReporting
@preconcurrency import KeystoneSDK

extension KeystoneHandlerClient {
    static let noOp = Self(
        decodeQR: { _ in nil },
        resetQRDecoder: { }
    )
}
