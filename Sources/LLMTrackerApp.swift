import SwiftUI

@main
struct LLMTrackerApp: App {
    @StateObject private var monitor = ServerMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            MenubarView(monitor: monitor)
        } label: {
            if let img = NSImage(named: "LLM_Tracker_iconTemplate") {
                let _ = { img.isTemplate = true }()
                Image(nsImage: img)
            } else {
                Image(systemName: "cpu")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
