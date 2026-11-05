import Foundation

enum NoteClipboardContentLoader {
    static func load(_ selection: NoteClipboardSelection, in directory: URL) throws -> NoteClipboardContent {
        let source = selection.source as NSString
        var parts: [NoteClipboardContent.Part] = []
        var cursor = 0
        for image in selection.images {
            if image.range.location > cursor {
                parts.append(.text(source.substring(with: NSRange(cursor..<image.range.location))))
            }
            parts.append(.image(try Data(contentsOf: image.reference.fileURL(in: directory))))
            cursor = NSMaxRange(image.range)
        }
        if cursor < source.length {
            parts.append(.text(source.substring(from: cursor)))
        }
        return NoteClipboardContent(parts: parts)
    }
}
