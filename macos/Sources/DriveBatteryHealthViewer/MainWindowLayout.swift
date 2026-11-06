import AppKit

/// A full-height background with actual content constrained to the system
/// content layout guide. Only the background extends behind the toolbar.
@MainActor
enum MainWindowLayout {
    static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

    static func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
    }
}
