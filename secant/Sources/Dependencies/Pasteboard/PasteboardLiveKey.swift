//
//  PasteboardLiveKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 13.11.2022.
//

import ComposableArchitecture
import UniformTypeIdentifiers
import UIKit

extension PasteboardClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        Self(
            setString: { UIPasteboard.general.string = $0.data },
            setSensitiveString: { value in
                UIPasteboard.general.setItems(
                    [[UTType.utf8PlainText.identifier: value.data]],
                    options: [
                        .localOnly: true,
                        .expirationDate: Date().addingTimeInterval(sensitiveClipboardLifetime)
                    ]
                )
            },
            getString: { UIPasteboard.general.string?.redacted }
        )
    }
}

/// Fifteen minutes: long enough to paste into a message, short enough that a link left on the
/// clipboard does not outlive the conversation it was meant for.
private let sensitiveClipboardLifetime: TimeInterval = 15 * 60
