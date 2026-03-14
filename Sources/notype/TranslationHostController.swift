import AppKit
import SwiftUI

@MainActor
final class TranslationHostController {
    private let panel: NSPanel

    init(controller: TranslationController) {
        let hostingController = NSHostingController(
            rootView: TranslationHostView(controller: controller)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.alphaValue = 0.001
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.orderFrontRegardless()

        self.panel = panel
    }
}
