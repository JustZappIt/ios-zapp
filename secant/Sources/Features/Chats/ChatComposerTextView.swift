//
//  ChatComposerTextView.swift
//  Zapp
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The composer's text field, as UIKit rather than SwiftUI.
///
/// A pasted image arrives through `UIResponder.paste(itemProviders:)`, which SwiftUI's `TextField`
/// cannot implement. Android reaches the same place through `contentReceiver`.
struct ChatComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String
    let maxLines: Int
    let onMediaPasted: (URL, UTType) -> Void

    func makeUIView(context: Context) -> MediaPastingTextView {
        let view = MediaPastingTextView()
        view.delegate = context.coordinator
        view.onMediaPasted = onMediaPasted
        view.font = Self.font
        view.textColor = UIColor(ZappColors.text.color(context.environment.colorScheme))
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        view.placeholderLabel.text = placeholder
        view.placeholderLabel.font = Self.font

        return view
    }

    func updateUIView(_ view: MediaPastingTextView, context: Context) {
        // Assigning unconditionally would reset the selection on every redraw.
        if view.text != text {
            view.text = text
        }

        view.onMediaPasted = onMediaPasted
        view.textColor = UIColor(ZappColors.text.color(context.environment.colorScheme))
        view.placeholderLabel.textColor = UIColor(ZappColors.textSubtle.color(context.environment.colorScheme))
        view.placeholderLabel.isHidden = !text.isEmpty
        view.maxHeight = Self.font.lineHeight * CGFloat(maxLines)

        // Only a change SwiftUI made may drive the responder: a tap focuses the field before the
        // binding catches up, and "correcting" that swallowed the tap.
        if context.coordinator.lastSeenFocus != isFocused {
            context.coordinator.lastSeenFocus = isFocused

            applyFocus(to: view)
        }
    }

    /// Measured against the proposed width; `bounds.width` is still zero on the first pass, which
    /// wraps every character onto its own line and snaps the field to `maxLines`.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MediaPastingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }

        return CGSize(width: width, height: uiView.height(fitting: width))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    /// Settled after the update: `becomeFirstResponder` moves the keyboard synchronously, and the
    /// binding write that provokes would re-enter the update placing this field.
    private func applyFocus(to view: MediaPastingTextView) {
        guard isFocused != view.isFirstResponder else { return }

        let wanted = $isFocused

        DispatchQueue.main.async { [weak view] in
            guard let view, wanted.wrappedValue != view.isFirstResponder else { return }

            if wanted.wrappedValue {
                guard view.window != nil else { return }

                view.becomeFirstResponder()
            } else {
                view.resignFirstResponder()
            }
        }
    }

    private static var font: UIFont {
        UIFont(name: FontFamily.Inter.regular.name, size: ZappTextStyle.body.size)
            ?? .systemFont(ofSize: ZappTextStyle.body.size)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var lastSeenFocus: Bool?

        private let text: Binding<String>
        private let isFocused: Binding<Bool>

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            (textView as? MediaPastingTextView)?.placeholderLabel.isHidden = !textView.text.isEmpty
            textView.invalidateIntrinsicContentSize()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let current = textView.text as NSString

            return current.replacingCharacters(in: range, with: text).count
                <= MediaPastingTextView.maxTextCharacters
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            report(focus: true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            report(focus: false)
        }

        private func report(focus: Bool) {
            guard isFocused.wrappedValue != focus else { return }

            DispatchQueue.main.async { [isFocused] in
                guard isFocused.wrappedValue != focus else { return }

                isFocused.wrappedValue = focus
            }
        }
    }
}

/// A text view that accepts images as well as text.
///
/// `pasteConfiguration` is what offers Paste for an image: the system asks the first responder
/// whether it accepts the type first. The stock keyboard has no GIF key — Apple's `#images` is a
/// Messages-only extension — so a GIF reaches the composer by paste or through the picker sheet.
final class MediaPastingTextView: UITextView {
    nonisolated static let maxTextCharacters = 16_000
    /// Every still type the encoder can ship. GIF is listed first because it is the one that
    /// must survive as-is; the others are re-encoded downstream.
    static let acceptedTypes: [UTType] = [.gif, .png, .jpeg, .image]

    var onMediaPasted: ((URL, UTType) -> Void)?
    var maxHeight: CGFloat = .greatestFiniteMagnitude
    private var isImportingMedia = false

    let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)

        pasteConfiguration = UIPasteConfiguration(
            acceptableTypeIdentifiers: Self.acceptedTypes.map(\.identifier)
        )

        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Grows with the text up to `maxLines`, then scrolls — the behaviour `lineLimit(1...5)`
    /// gave the SwiftUI field.
    func height(fitting width: CGFloat) -> CGFloat {
        min(sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height, maxHeight)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height(fitting: bounds.width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let fitted = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
        let shouldScroll = fitted > maxHeight + 0.5

        if isScrollEnabled != shouldScroll {
            isScrollEnabled = shouldScroll
        }
    }

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        super.canPaste(itemProviders) || itemProviders.contains { provider in
            Self.acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard !isImportingMedia else { return }

        let media = itemProviders.filter { provider in
            Self.acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }

        guard !media.isEmpty else {
            super.paste(itemProviders: itemProviders)
            return
        }

        // A paste can contain the same image in several representations. Importing every
        // provider concurrently multiplies peak memory and sends duplicates, so one user
        // gesture always produces at most one attachment.
        guard let provider = media.first else { return }

        isImportingMedia = true
        load(provider)
    }

    /// The most specific type wins, so an animated GIF is never taken as a generic image and
    /// flattened on the way out.
    private func load(_ provider: NSItemProvider) {
        guard
            let type = Self.acceptedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) })
        else {
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] sourceURL, error in
            guard let sourceURL, error == nil else {
                LoggerProxy.error("Chat composer could not read pasted media: \(error?.localizedDescription ?? "no data")")
                Task { @MainActor [weak self] in self?.isImportingMedia = false }
                return
            }

            let importedURL: URL

            do {
                importedURL = try ChatMediaTemporaryFiles.importFile(at: sourceURL)
            } catch {
                LoggerProxy.error("Chat composer rejected pasted media: \(error.localizedDescription)")
                Task { @MainActor [weak self] in self?.isImportingMedia = false }
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    ChatMediaTemporaryFiles.remove(importedURL)
                    return
                }

                self.isImportingMedia = false
                self.onMediaPasted?(importedURL, type)
            }
        }
    }
}
