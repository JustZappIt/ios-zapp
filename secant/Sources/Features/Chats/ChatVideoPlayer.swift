//
//  ChatVideoPlayer.swift
//  Zapp
//
//  Fullscreen playback for a video message, presented from the room's media-viewer slot. AVKit
//  supplies the transport controls; the close button matches `ChatImageViewer`'s.
//

import AVKit
import SwiftUI
import ZappMessaging

/// The room's one fullscreen media slot: a video opens the player, everything else the image
/// viewer. One cover with a switch rather than a second `fullScreenCover`, which SwiftUI would
/// not reliably present from the same view.
struct ChatMediaViewer: View {
    let message: ZMMessage
    let onDismiss: () -> Void

    var body: some View {
        if ChatMessageKind.of(message) == .video {
            ChatVideoPlayer(message: message, onDismiss: onDismiss)
        } else {
            ChatImageViewer(message: message, onDismiss: onDismiss)
        }
    }
}

struct ChatVideoPlayer: View {
    private enum Constants {
        static let closeIcon: CGFloat = 20
        static let closeTarget: CGFloat = 44
    }

    let message: ZMMessage
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var didFail = false
    @State private var previousAudioCategory: AVAudioSession.Category?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else if didFail {
                Text(String(localizable: .chatRoomVideoFailed))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button(action: onDismiss) {
                Asset.Assets.Icons.xClose.image
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: Constants.closeIcon, height: Constants.closeIcon)
                    .foregroundColor(.white)
                    .frame(width: Constants.closeTarget, height: Constants.closeTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .generalClose))
            .padding(Design.Spacing._lg)
        }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        guard player == nil else { return }

        guard let url = ChatVideoPlayback.fileURL(for: message) else {
            didFail = true
            return
        }

        // A video the user chose to play should be heard even with the ring switch on silent, as
        // in other messengers. The app's own category is restored on close, and other apps'
        // audio is told it may resume.
        let session = AVAudioSession.sharedInstance()
        previousAudioCategory = session.category
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player = nil

        guard let previousAudioCategory else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(previousAudioCategory)
        self.previousAudioCategory = nil
    }
}
