import AppKit

extension NSAttributedString.Key {
    static let noteImage = NSAttributedString.Key("oncast.note.image")
}

final class NoteImageDecoration: NSObject, Sendable {
    let image: NSImage
    let size: CGSize

    init(image: NSImage, width: CGFloat) {
        self.image = image
        let scale = min(1, width / image.size.width)
        size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    @MainActor var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = size.height
        paragraph.maximumLineHeight = size.height
        paragraph.paragraphSpacing = Theme.Spacing.md
        paragraph.lineBreakMode = .byClipping
        return [
            .font: NoteMarkdownTypography.hidden, .foregroundColor: NSColor.clear,
            .paragraphStyle: paragraph, .noteImage: self
        ]
    }
}

final class NoteImageLayoutFragment: NSTextLayoutFragment {
    let decoration: NoteImageDecoration

    init(textElement: NSTextElement, decoration: NoteImageDecoration) {
        self.decoration = decoration
        super.init(textElement: textElement, range: textElement.elementRange)
    }

    required init?(coder: NSCoder) { nil }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(CGRect(origin: .zero, size: decoration.size))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        decoration.image.draw(
            in: CGRect(origin: point, size: decoration.size), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
