//
//  ChatContactsTestKey.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

extension ChatContactsClient: TestDependencyKey {
    static let testValue = ChatContactsClient(
        all: { _ in .empty },
        save: { _, _ in .empty },
        delete: { _, _ in .empty },
        setBlocked: { _, _, _, _ in .empty },
        resetAccount: { _ in }
    )
}
