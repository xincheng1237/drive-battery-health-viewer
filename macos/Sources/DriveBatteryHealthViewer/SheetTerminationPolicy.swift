import AppKit
import SwiftUI

/// Configure only the window owned by this sheet, using AppKit's public policy.
/// Reading information must not block normal Quit or system termination.
struct SheetTerminationPolicy: NSViewRepresentable {
    let preventsTermination: Bool

    func makeNSView(context: Context) -> PolicyView {
        PolicyView(preventsTermination: preventsTermination)
    }

    func updateNSView(_ view: PolicyView, context: Context) {
        view.preventsTermination = preventsTermination
        view.applyPolicy()
    }

    final class PolicyView: NSView {
        var preventsTermination: Bool

        init(preventsTermination: Bool) {
            self.preventsTermination = preventsTermination
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyPolicy()
        }

        func applyPolicy() {
            window?.preventsApplicationTerminationWhenModal = preventsTermination
        }
    }
}
