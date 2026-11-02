import AppKit
import SwiftUI

extension AppModel {
    func writeSnapshots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var shots: [(String, CGFloat, CGFloat, AnyView)] = [
            ("review.png", 980, 720, AnyView(ReviewWindow().environmentObject(self))),
            ("summary-en.png", 860, 680, AnyView(SummaryScreen(initialPage: 0).environmentObject(self))),
            ("summary-zh.png", 860, 680, AnyView(SummaryScreen(initialPage: 1).environmentObject(self))),
            ("result.png", 560, 760, AnyView(ResultView().environmentObject(self))),
            ("menu.png", 420, 720, AnyView(MenuPanel().environmentObject(self))),
            ("settings.png", 460, 720, AnyView(SettingsView().environmentObject(self))),
        ]
        if let only = CommandLine.arguments.firstIndex(of: "--snapshot-only"),
           CommandLine.arguments.indices.contains(CommandLine.arguments.index(after: only)) {
            let name = CommandLine.arguments[CommandLine.arguments.index(after: only)]
            shots = shots.filter { $0.0 == name }
        }
        capture(shots, index: 0, directory: directory)
    }

    private func capture(_ shots: [(String, CGFloat, CGFloat, AnyView)], index: Int, directory: URL) {
        guard index < shots.count else {
            fputs("snapshots done\n", stderr)
            NSApp.terminate(nil)
            return
        }
        let shot = shots[index]
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: shot.1, height: shot.2),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = shot.0
        window.backgroundColor = Palette.nsPaper
        window.contentViewController = NSHostingController(rootView: shot.3)
        window.setContentSize(NSSize(width: shot.1, height: shot.2))
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.writeWindow(window, to: directory.appendingPathComponent(shot.0))
            window.orderOut(nil)
            self?.capture(shots, index: index + 1, directory: directory)
        }
    }

    private func writeWindow(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else {
            fputs("snapshot missing view \(url.lastPathComponent)\n", stderr)
            return
        }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            fputs("snapshot no bitmap \(url.lastPathComponent)\n", stderr)
            return
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url)
            fputs("snapshot \(url.lastPathComponent) \(png.count)\n", stderr)
        } catch {
            fputs("snapshot write \(url.lastPathComponent) \(error)\n", stderr)
        }
    }
}
