import AppKit
import SwiftUI

enum WindowKind: String {
    case review
    case settings
}

@MainActor
final class WindowPresenter {
    private var model: AppModel?
    private var windows: [WindowKind: NSWindow] = [:]

    func attach(_ model: AppModel) {
        self.model = model
    }

    func show(_ kind: WindowKind) {
        guard let model else { return }
        NSApp.activate(ignoringOtherApps: true)
        let window: NSWindow
        if let existing = windows[kind] {
            window = existing
        } else {
            window = makeWindow(kind, model: model)
            windows[kind] = window
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow(_ kind: WindowKind, model: AppModel) -> NSWindow {
        let root: AnyView
        let title: String
        let size: NSSize
        let minSize: NSSize
        switch kind {
        case .review:
            root = AnyView(ReviewWindow().environmentObject(model))
            title = "纠正本"
            size = NSSize(width: 980, height: 720)
            minSize = NSSize(width: 860, height: 560)
        case .settings:
            root = AnyView(SettingsView().environmentObject(model))
            title = "设置"
            size = NSSize(width: 460, height: 560)
            minSize = NSSize(width: 400, height: 480)
        }
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.nsPaper
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}
