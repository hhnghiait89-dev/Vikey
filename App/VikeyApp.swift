import SwiftUI

@main
struct VikeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // macOS 12 backport (fork patch): MenuBarExtra is macOS 13+, so the menu bar
        // item is an AppKit NSStatusItem with a hand-built NSMenu, installed by
        // AppDelegate (see installStatusItem). The Settings scene is only a
        // placeholder so the SwiftUI lifecycle and the .commands below still work.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("Giới thiệu về Vikey") { AboutPanel.show() }   // with the credits
                    Button("Ghi nhận…") { Windows.acknowledgements.show() }
                    Button("Kiểm tra cập nhật…") { Updater.shared.checkForUpdates() }
                    Divider()
                    DebugMenu()
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Mở Vikey…") { Windows.main.show() }
                        .keyboardShortcut(",")
                }
            }

    }
}
