import SwiftUI

@main
struct FreeDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var displayManager = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(displayManager)
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}
