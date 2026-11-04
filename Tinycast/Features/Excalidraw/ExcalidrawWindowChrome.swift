import AppKit

@MainActor
final class ExcalidrawWindowChrome: WindowChrome {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("ExcalidrawWindow")

    func install(in window: NSWindow) {
        window.identifier = Self.windowIdentifier
        window.styleMask.remove(.fullSizeContentView)
        window.toolbar = nil
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.Colors.excalidrawCanvas)
        window.isMovableByWindowBackground = false
    }
}
