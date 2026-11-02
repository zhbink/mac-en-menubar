import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var phaseCancellable: AnyCancellable?
    private var anchorWindow: NSWindow?
    private weak var model: AppModel?

    func install(model: AppModel) {
        if statusItem != nil { return }
        self.model = model
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.action = #selector(toggle)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        apply(model.phase)

        let hosting = NSHostingController(rootView: MenuPanel().environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
        popover.delegate = self
        self.popover = popover

        phaseCancellable = model.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.apply(phase)
            }
    }

    func show() {
        guard let popover, statusItem?.button != nil, !popover.isShown else { return }
        // Activate first, then show on the next turn. A transient popover
        // opened in the same turn as activation is dismissed immediately.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.present()
        }
    }

    func close() {
        statusItem?.button?.isHighlighted = false
        anchorWindow?.orderOut(nil)
        guard let popover, popover.isShown else { return }
        let wasAnimating = popover.animates
        popover.animates = false
        popover.performClose(nil)
        popover.animates = wasAnimating
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            statusItem?.button?.isHighlighted = false
            anchorWindow?.orderOut(nil)
        }
    }

    private func present() {
        guard let popover, !popover.isShown else { return }
        let intended = visibleStatusItemFrame()
        guard let anchor = anchorView() else { return }
        let wasAnimating = popover.animates
        popover.animates = false
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.animates = wasAnimating
        statusItem?.button?.isHighlighted = true
        guard let intended else { return }
        nudgePopover(below: intended)
        DispatchQueue.main.async { [weak self] in
            self?.nudgePopover(below: intended)
        }
    }

    /// NSPopover sometimes anchors to a menu-bar clone on another display.
    /// After it opens, move the panel under the icon on the screen with the pointer.
    private func nudgePopover(below anchor: NSRect) {
        guard let window = popover?.contentViewController?.view.window else { return }
        let size = window.frame.size
        guard size.width > 40, size.height > 40 else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        guard let screen else { return }
        let bounds = screen.visibleFrame
        var x = anchor.midX - size.width / 2
        let minX = bounds.minX + 8
        let maxX = bounds.maxX - size.width - 8
        x = min(max(x, minX), max(minX, maxX))
        var y = anchor.minY - size.height - 4
        if y < bounds.minY + 8 {
            y = bounds.minY + 8
        }
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// The status item is drawn on every menu bar, but `button` often belongs to a
    /// display whose menu bar is not visible. Anchor the popover to the icon on
    /// the screen under the pointer.
    private func anchorView() -> NSView? {
        guard let button = statusItem?.button else { return nil }
        guard let frame = visibleStatusItemFrame() else { return button }
        if let window = button.window, window.isVisible, window.frame.intersects(frame.insetBy(dx: -4, dy: -4)) {
            return button
        }
        let window = anchorWindow ?? makeAnchorWindow()
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        return window.contentView
    }

    private func makeAnchorWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.alphaValue = 0.01
        window.contentView = NSView()
        anchorWindow = window
        return window
    }

    private func visibleStatusItemFrame() -> NSRect? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let mouse = NSEvent.mouseLocation
        var best: NSRect?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int, owner == Int(pid) else { continue }
            if let number = entry[kCGWindowNumber as String] as? Int, number == anchorWindow?.windowNumber {
                continue
            }
            guard let raw = entry[kCGWindowBounds as String] as? NSDictionary else { continue }
            var quartz = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(raw, &quartz) else { continue }
            guard quartz.width > 8, quartz.width < 80, quartz.height > 8, quartz.height < 50 else { continue }
            let frame = appKitFrame(fromQuartz: quartz)
            let distance = hypot(frame.midX - mouse.x, frame.midY - mouse.y)
            if distance < bestDistance {
                bestDistance = distance
                best = frame
            }
        }
        return best
    }

    private func appKitFrame(fromQuartz quartz: CGRect) -> NSRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        let height = primary?.frame.height ?? quartz.height
        return NSRect(
            x: quartz.origin.x,
            y: height - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }

    @objc private func toggle() {
        if popover?.isShown == true {
            close()
        } else {
            show()
        }
    }

    private func apply(_ phase: WorkPhase) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch phase {
        case .idle:
            symbol = "character.book.closed"
        case .capturing:
            symbol = "viewfinder"
        case .analyzing, .digesting, .followingUp:
            symbol = "ellipsis.circle"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Gloss")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        button.title = phase == .idle ? "" : "…"
    }
}
