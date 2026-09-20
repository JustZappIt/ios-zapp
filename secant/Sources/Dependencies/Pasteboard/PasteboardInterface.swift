//
//  PasteboardInterface.swift
//  Zashi
//
//  Created by Lukáš Korba on 13.11.2022.
//

import ComposableArchitecture

extension DependencyValues {
    var pasteboard: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}

@DependencyClient
struct PasteboardClient {
    var setString: @Sendable (RedactableString) -> Void
    /// For a bearer secret, such as a group invite link: this device only, and gone in fifteen
    /// minutes, so it never rides the Universal Clipboard to another device or sits there for the
    /// rest of the day.
    var setSensitiveString: @Sendable (RedactableString) -> Void
    var getString: @Sendable () -> RedactableString?
}
