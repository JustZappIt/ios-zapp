//
//  ChatComposerTextView.swift
//  Zapp
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The composer's text field, as UIKit rather than SwiftUI.
///
/// SwiftUI's `TextField` has no way to receive media: the GIF key on the system keyboard, and a
/// pasted image, both arrive through `UIResponder.paste(itemProviders:)`, which only a UIKit
/// responder can implement. That is the whole reason this bridge exists — Android reaches the
/// same place through `contentReceiver`.
struct ChatComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String
    let maxLines: Int
    let onMediaPasted: (Data, UTType) -> Void

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

        if isFocused, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isFocused, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    private static var font: UIFont {
        UIFont(name: FontFamily.Inter.regular.name, size: ZappTextStyle.body.size)
            ?? .systemFont(ofSize: ZappTextStyle.body.size)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !isFocused.wrappedValue else { return }
            isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard isFocused.wrappedValue else { return }
            isFocused.wrappedValue = false
        }
    }
}

/// A text view that accepts images as well as text.
///
/// `pasteConfiguration` is what makes the keyboard's GIF key light up: the system asks the first
/// responder whether it accepts the type before offering to insert it.
final class MediaPastingTextView: UITextView {
    /// Every still type the encoder can ship. GIF is listed first because it is the one that
    /// must survive as-is; the others are re-encoded downstream.
    static let acceptedTypes: [UTType] = [.gif, .png, .jpeg, .image]

    var onMediaPasted: ((Data, UTType) -> Void)?
    var maxHeight: CGFloat = .greatestFiniteMagnitude

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
    override var intrinsicContentSize: CGSize {
        let fitted = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let height = min(fitted.height, maxHeight)

        isScrollEnabled = fitted.height > maxHeight

        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        super.canPaste(itemProviders) || itemProviders.contains { provider in
            Self.acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        let media = itemProviders.filter { provider in
            Self.acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }

        guard !media.isEmpty else {
            super.paste(itemProviders: itemProviders)
            return
        }

        for provider in media {
            load(provider)
        }
    }

    /// The most specific type wins, so an animated GIF is never taken as a generic image and
    /// flattened on the way out.
    private func load(_ provider: NSItemProvider) {
        guard
            let type = Self.acceptedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) })
        else {
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, error in
            guard let data, error == nil else {
                LoggerProxy.error("Chat composer could not read pasted media: \(error?.localizedDescription ?? "no data")")
                return
            }

            Task { @MainActor [weak self] in
                self?.onMediaPasted?(data, type)
            }
        }
    }
}
