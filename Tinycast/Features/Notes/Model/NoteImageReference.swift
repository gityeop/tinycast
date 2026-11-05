import Foundation

struct NoteImageReference: Sendable, Equatable, Hashable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }

    init?(destination: String) {
        guard destination.hasPrefix("images/"), destination.hasSuffix(".png"),
            let id = UUID(uuidString: String(destination.dropFirst(7).dropLast(4)))
        else { return nil }
        self.id = id
    }

    var destination: String { "images/\(id.uuidString).png" }
    var markdown: String { "![Image](\(destination))" }

    func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(destination)
    }
}
