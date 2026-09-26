import AppKit
import SwiftUI

@main
struct __NAME__App: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup("__DISPLAY_NAME__") {
            ContentView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ItemListModel()

    // `swift run` starts a bare executable, so make it a regular app and bring its window to the front.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    // Reload so changes made with the CLI show up when the app comes back to the front.
    func applicationDidBecomeActive(_ notification: Notification) {
        model.reload()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
