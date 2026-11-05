import Foundation

/// What `NoteTextView` asks of the editor that owns it: rendering state and lifecycle calls.
@MainActor
protocol NoteTextViewEditing: AnyObject {
    var rendersMarkdown: Bool { get }
    /// The parse of the text view's current source.
    var markdown: NoteMarkdown { get }
    var notesDirectory: URL? { get }
    func focusChanged()
    func appearanceChanged()
    func dragSelectionEnded()
    func layoutWidthChanged()
    func pasteImage(_ png: Data)
    func imagePasteFailed()
    func pasteContent(_ content: NoteClipboardContent)
    func clipboardCopyFailed()
}
