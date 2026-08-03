//
//  ChatLinkPreviewInterface.swift
//  Zapp
//

import ComposableArchitecture

extension DependencyValues {
    var chatLinkPreview: ChatLinkPreviewClient {
        get { self[ChatLinkPreviewClient.self] }
        set { self[ChatLinkPreviewClient.self] = newValue }
    }
}

@DependencyClient
struct ChatLinkPreviewClient {
    /// `nil` whenever the URL is unsafe to fetch, the response is not previewable HTML, or the
    /// page carries no Open Graph metadata worth showing.
    var load: @Sendable (_ url: String) async -> ChatLinkPreview?
}
