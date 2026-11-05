import AppKit

/// Keep scrolling content inside the system content area, below window chrome.
@MainActor
enum MainWindowLayout {
    static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    static func configure(_ window: NSWindow) {
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
    }
}
