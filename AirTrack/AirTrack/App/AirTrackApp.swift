import AppKit
import SwiftUI

@main
struct AirTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AirTrack") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 600)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the debug window quits the app, so the camera is never left running in the background.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
