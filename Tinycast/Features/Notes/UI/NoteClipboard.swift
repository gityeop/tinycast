import AppKit

@MainActor
enum NoteClipboard {
    static func plainText(_ content: NoteClipboardContent) -> String {
        content.parts.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            return text
        }.joined()
    }

    static func html(_ content: NoteClipboardContent) -> String {
        let body = content.parts.map { part in
            switch part {
            case .text(let text):
                text.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>")
            case .image(let png):
                "<img src=\"data:image/png;base64,\(png.base64EncodedString())\" alt=\"Image\">"
            }
        }.joined()
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head>"
            + "<body style=\"white-space:pre-wrap\">\(body)</body></html>"
    }

    static func singleImage(_ content: NoteClipboardContent) -> Data? {
        let images = content.parts.compactMap { part -> Data? in
            guard case .image(let png) = part else { return nil }
            return png
        }
        return images.count == 1 ? images[0] : nil
    }

    static func encode(_ content: NoteClipboardContent) throws -> Data {
        let rich = NSMutableAttributedString(string: "")
        for (index, part) in content.parts.enumerated() {
            switch part {
            case .text(let text):
                rich.append(NSAttributedString(string: text, attributes: [.font: NoteMarkdownTypography.body]))
            case .image(let png):
                let wrapper = FileWrapper(regularFileWithContents: png)
                wrapper.preferredFilename = "image-\(index).png"
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                rich.append(NSAttributedString(attachment: attachment))
            }
        }
        return try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }

    static func decode(_ data: Data) throws -> NoteClipboardContent {
        let rich = try NSAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil)
        var parts: [NoteClipboardContent.Part] = []
        var cursor = 0
        while cursor < rich.length {
            var range = NSRange()
            let attachment = rich.attribute(.attachment, at: cursor, effectiveRange: &range)
                as? NSTextAttachment
            if let attachment {
                guard let data = attachment.fileWrapper?.regularFileContents,
                    let bitmap = NSBitmapImageRep(data: data),
                    let png = bitmap.representation(using: .png, properties: [:])
                else { throw CocoaError(.fileReadCorruptFile) }
                parts.append(.image(png))
            } else {
                parts.append(.text((rich.string as NSString).substring(with: range)))
            }
            cursor = NSMaxRange(range)
        }
        return NoteClipboardContent(parts: parts)
    }
}
