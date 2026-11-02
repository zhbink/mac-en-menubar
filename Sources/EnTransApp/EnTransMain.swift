import EnTransCore
import SwiftUI

@main
struct EnTransMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // The menu bar icon is an NSStatusItem so a finished capture can open it.
        // This hidden scene only keeps the process alive.
        WindowGroup {
            LaunchAnchor()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct LaunchAnchor: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onAppear(perform: hideAnchorWindow)
    }

    private func hideAnchorWindow() {
        for window in NSApp.windows where window.level == .normal {
            let size = window.frame.size
            if size.width < 80, size.height < 80 {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
    }
}
