import Foundation

struct NoteClipboardContent: Sendable {
    enum Part: Sendable {
        case text(String)
        case image(Data)
    }

    let parts: [Part]
}

struct NoteClipboardSelection: Sendable {
    struct Image: Sendable {
        let range: NSRange
        let reference: NoteImageReference
    }

    let source: String
    let images: [Image]

    init?(source: String, range: NSRange) {
        let images = NoteMarkdownParser.parse(source).lines.compactMap { line -> Image? in
            guard case .image(let reference) = line.kind,
                NSIntersectionRange(range, line.contentRange) == line.contentRange
            else { return nil }
            return Image(
                range: NSRange(
                    location: line.contentRange.location - range.location,
                    length: line.contentRange.length),
                reference: reference)
        }
        guard !images.isEmpty else { return nil }
        self.source = (source as NSString).substring(with: range)
        self.images = images
    }
}
