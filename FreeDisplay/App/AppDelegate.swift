import AppKit
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 确保只在菜单栏显示，不出现在 Dock
        // LSUIElement 在 Info.plist 中设置，这里做备份
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGDisplayRestoreColorSyncSettings()
    }
}
