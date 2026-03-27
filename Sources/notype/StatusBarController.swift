import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private let translationHost: TranslationHostController
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.translationHost = TranslationHostController(controller: model.translationController)

        configureStatusItem()
        configurePopover()
        bindModel()
        refreshButtonAppearance()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        configureStatusMenu()
    }

    private func configureStatusMenu() {
        statusMenu.removeAllItems()
        statusMenu.addItem(
            withTitle: "打开 NoType",
            action: #selector(openPopoverFromMenu(_:)),
            keyEquivalent: ""
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "退出 NoType",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        statusMenu.items.forEach { $0.target = self }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(model: model)
        )
    }

    private func bindModel() {
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshButtonAppearance()
            }
            .store(in: &cancellables)
    }

    private func refreshButtonAppearance() {
        guard let button = statusItem.button else { return }

        let indicator: String
        switch model.phase {
        case .idle:
            indicator = "●"
        case .preparing:
            indicator = "…"
        case .listening:
            indicator = "◉"
        case .processing:
            indicator = "◌"
        case .failed:
            indicator = "▲"
        }

        button.title = "\(indicator) \(model.mode.shortLabel)"
        button.toolTip = "NoType - \(model.statusSummary) - \(model.hotKeyDisplayString)"
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = statusMenu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc
    private func openPopoverFromMenu(_ sender: AnyObject?) {
        togglePopover(sender)
    }

    @objc
    private func quitFromMenu(_ sender: AnyObject?) {
        model.quitApplication()
    }
}
