import SwiftData
import SwiftUI
import UIKit

private final class AutomaticallyFocusingTextView: UITextView {
    var automaticallyFocus = false
    private var hasRequestedFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, automaticallyFocus, !hasRequestedFocus else { return }
        hasRequestedFocus = true
        DispatchQueue.main.async { [weak self] in
            self?.becomeFirstResponder()
        }
    }
}

@MainActor
final class RichTextFormattingController: ObservableObject {
    @Published private(set) var fontFamily = "New York"
    @Published private(set) var fontSize: CGFloat = 17
    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderlined = false
    @Published private(set) var isLinked = false
    @Published private(set) var hasTextSelection = false

    weak var textView: UITextView?
    private var pendingSelectionRefresh: Task<Void, Never>?

    func attach(_ textView: UITextView) {
        self.textView = textView
        scheduleSelectionStateRefresh()
    }

    func scheduleSelectionStateRefresh() {
        pendingSelectionRefresh?.cancel()
        pendingSelectionRefresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.refreshSelectionState()
        }
    }

    func applyFontFamily(_ family: String) {
        mutateFont { font in
            let descriptor = font.fontDescriptor.withFamily(family)
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        fontFamily = family
    }

    func applyFontSize(_ size: CGFloat) {
        mutateFont { font in
            UIFont(descriptor: font.fontDescriptor, size: size)
        }
        fontSize = size
    }

    func toggleBold() {
        setTrait(.traitBold, enabled: !isBold)
    }

    func toggleItalic() {
        setTrait(.traitItalic, enabled: !isItalic)
    }

    func toggleUnderline() {
        guard let textView else { return }
        let enabled = !isUnderlined
        if enabled {
            applyAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue)
            textView.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            removeAttribute(.underlineStyle)
            textView.typingAttributes.removeValue(forKey: .underlineStyle)
        }
        isUnderlined = enabled
        commitChange()
    }

    var currentLinkURL: URL? {
        guard let textView else { return nil }
        return representativeAttributes(in: textView)[.link] as? URL
    }

    @discardableResult
    func applyLink(_ address: String) -> Bool {
        guard let textView, textView.selectedRange.length > 0,
              let url = normalizedURL(from: address) else { return false }
        applyAttribute(.link, value: url)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        isLinked = true
        commitChange()
        return true
    }

    func isValidLinkAddress(_ address: String) -> Bool {
        normalizedURL(from: address) != nil
    }

    func removeLink() {
        guard let textView, textView.selectedRange.length > 0 else { return }
        let selectedRange = textView.selectedRange
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        mutable.removeAttribute(.link, range: selectedRange)
        textView.attributedText = mutable
        textView.selectedRange = selectedRange
        isLinked = false
        commitChange()
    }

    func refreshSelectionState() {
        guard let textView else { return }
        let attributes = representativeAttributes(in: textView)
        let font = (attributes[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        fontFamily = font.familyName
        fontSize = font.pointSize
        isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
        isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        let underline = (attributes[.underlineStyle] as? NSNumber)?.intValue
            ?? (attributes[.underlineStyle] as? Int)
            ?? 0
        isUnderlined = underline != 0
        isLinked = attributes[.link] != nil
        hasTextSelection = textView.selectedRange.length > 0
    }

    private func setTrait(_ trait: UIFontDescriptor.SymbolicTraits, enabled: Bool) {
        mutateFont { font in
            var traits = font.fontDescriptor.symbolicTraits
            if enabled {
                traits.insert(trait)
            } else {
                traits.remove(trait)
            }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        refreshSelectionState()
    }

    private func mutateFont(_ transform: (UIFont) -> UIFont) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange

        if selectedRange.length == 0 {
            let current = (textView.typingAttributes[.font] as? UIFont)
                ?? UIFont.preferredFont(forTextStyle: .body)
            textView.typingAttributes[.font] = transform(current)
        } else {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
                let current = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                mutable.addAttribute(.font, value: transform(current), range: range)
            }
            textView.attributedText = mutable
            textView.selectedRange = selectedRange
        }

        commitChange()
        refreshSelectionState()
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard let textView, textView.selectedRange.length > 0 else { return }
        let selectedRange = textView.selectedRange
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        mutable.addAttribute(key, value: value, range: selectedRange)
        textView.attributedText = mutable
        textView.selectedRange = selectedRange
    }

    private func removeAttribute(_ key: NSAttributedString.Key) {
        guard let textView, textView.selectedRange.length > 0 else { return }
        let selectedRange = textView.selectedRange
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        mutable.removeAttribute(key, range: selectedRange)
        textView.attributedText = mutable
        textView.selectedRange = selectedRange
    }

    private func representativeAttributes(in textView: UITextView) -> [NSAttributedString.Key: Any] {
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0, textView.attributedText.length > 0 {
            return textView.attributedText.attributes(at: selectedRange.location, effectiveRange: nil)
        }
        if selectedRange.location > 0, textView.attributedText.length > 0 {
            return textView.attributedText.attributes(at: selectedRange.location - 1, effectiveRange: nil)
        }
        return textView.typingAttributes
    }

    private func normalizedURL(from address: String) -> URL? {
        LinkAddress.normalizedURL(from: address)
    }

    private func commitChange() {
        guard let textView else { return }
        textView.delegate?.textViewDidChange?(textView)
    }
}

enum LinkAddress {
    static func normalizedURL(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") || trimmed.hasPrefix("mailto:")
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.scheme != nil else { return nil }
        return url
    }
}

struct RichTextEditor: UIViewRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Bindable var block: ContentBlock
    let controller: RichTextFormattingController
    let minimumHeight: CGFloat
    let automaticallyFocus: Bool
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            block: block,
            controller: controller,
            modelContext: modelContext,
            onChange: onChange
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = AutomaticallyFocusingTextView()
        textView.automaticallyFocus = automaticallyFocus
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.alwaysBounceHorizontal = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.accessibilityLabel = block.type == .heading ? "Heading text" : "Paragraph text"
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let keyboardToolbar = UIToolbar()
        keyboardToolbar.items = [
            UIBarButtonItem(
                barButtonSystemItem: .flexibleSpace,
                target: nil,
                action: nil
            ),
            UIBarButtonItem(
                title: "Done",
                style: .plain,
                target: context.coordinator,
                action: #selector(Coordinator.dismissKeyboard(_:))
            ),
        ]
        keyboardToolbar.sizeToFit()
        textView.inputAccessoryView = keyboardToolbar

        let attributedText = decodedAttributedText(for: block)
        textView.attributedText = attributedText
        textView.typingAttributes = defaultAttributes(for: block)
        controller.attach(textView)
        return textView
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: max(fittingSize.height, minimumHeight))
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.block = block
        context.coordinator.modelContext = modelContext
        context.coordinator.onChange = onChange

        if !textView.isFirstResponder, textView.text != block.text {
            textView.attributedText = decodedAttributedText(for: block)
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        coordinator.commitPendingUndo()
        textView.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        private struct TextSnapshot {
            let text: String
            let attributedTextData: Data?

            func differs(from other: TextSnapshot) -> Bool {
                text != other.text || attributedTextData != other.attributedTextData
            }
        }

        var block: ContentBlock
        let controller: RichTextFormattingController
        var modelContext: ModelContext
        var onChange: () -> Void
        private var pendingOriginalSnapshot: TextSnapshot?
        private var pendingCommitTask: Task<Void, Never>?

        init(
            block: ContentBlock,
            controller: RichTextFormattingController,
            modelContext: ModelContext,
            onChange: @escaping () -> Void
        ) {
            self.block = block
            self.controller = controller
            self.modelContext = modelContext
            self.onChange = onChange
        }

        func textViewDidChange(_ textView: UITextView) {
            if pendingOriginalSnapshot == nil {
                pendingOriginalSnapshot = snapshot(of: block)
            }

            schedulePendingUndoCommit()
            if textView.text.last?.isWhitespace == true {
                commitPendingUndo()
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            controller.scheduleSelectionStateRefresh()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            commitPendingUndo()
        }

        @objc func dismissKeyboard(_ sender: UIBarButtonItem) {
            commitPendingUndo()
            controller.textView?.resignFirstResponder()
        }

        private func snapshot(of block: ContentBlock) -> TextSnapshot {
            TextSnapshot(
                text: block.text,
                attributedTextData: block.attributedTextData
            )
        }

        private func schedulePendingUndoCommit() {
            pendingCommitTask?.cancel()
            pendingCommitTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                self?.commitPendingUndo()
            }
        }

        func commitPendingUndo() {
            pendingCommitTask?.cancel()
            pendingCommitTask = nil
            guard let originalSnapshot = pendingOriginalSnapshot,
                  let textView = controller.textView else { return }
            pendingOriginalSnapshot = nil
            let currentSnapshot = TextSnapshot(
                text: textView.text,
                attributedTextData: Self.archive(textView.attributedText)
            )
            guard originalSnapshot.differs(from: currentSnapshot) else { return }

            if let undoManager = modelContext.undoManager {
                undoManager.beginUndoGrouping()
                block.text = currentSnapshot.text
                block.attributedTextData = currentSnapshot.attributedTextData
                onChange()
                undoManager.endUndoGrouping()
                undoManager.setActionName("Edit Text")
            } else {
                block.text = currentSnapshot.text
                block.attributedTextData = currentSnapshot.attributedTextData
                onChange()
            }
        }

        private static func archive(_ attributedText: NSAttributedString) -> Data? {
            try? NSKeyedArchiver.archivedData(
                withRootObject: attributedText,
                requiringSecureCoding: true
            )
        }

    }

    private func decodedAttributedText(for block: ContentBlock) -> NSAttributedString {
        if let data = block.attributedTextData,
           let decoded = try? NSKeyedUnarchiver.unarchivedObject(
               ofClass: NSAttributedString.self,
               from: data
           ) {
            return decoded
        }

        return NSAttributedString(string: block.text, attributes: defaultAttributes(for: block))
    }

    private func defaultAttributes(for block: ContentBlock) -> [NSAttributedString.Key: Any] {
        var descriptor = UIFontDescriptor(name: block.fontFamily, size: block.fontSize)
        var traits = descriptor.symbolicTraits
        if block.isBold { traits.insert(.traitBold) }
        if block.isItalic { traits.insert(.traitItalic) }
        descriptor = descriptor.withSymbolicTraits(traits) ?? descriptor

        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(descriptor: descriptor, size: block.fontSize),
            .foregroundColor: UIColor.label,
        ]
        if block.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }
}
