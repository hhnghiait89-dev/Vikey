import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // macOS 12 backport (fork patch): the NSStatusItem that replaces MenuBarExtra.
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // before anything else: no event tap, no windows, no focus taken (it runs while others use the Mac)
        if let dir = UserDefaults.standard.string(forKey: "emojiSelfTest") { EmojiSelfTest.run(dir: dir); return }
        if let dir = UserDefaults.standard.string(forKey: "renderMainWindow") { MainWindowProposals.run(dir: dir); return }
        if UserDefaults.standard.bool(forKey: "crashSelfTest") { fatalError("Vikey crash self-test") }   // -crashSelfTest YES
        #endif
        Migration.fromOpenKeyIfNeeded()
        // people who already use Vikey (permission granted) don't get the first-run guide on update
        if UserDefaults.standard.object(forKey: OnboardingView.doneKey) == nil && VikeyCore.isAccessibilityTrusted() {
            UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
        }
        AppState.shared.startIfPossible()
        _ = Updater.shared                     // starts Sparkle: daily update checks
        EmojiPicker.shared.install()
        CrashReporter.checkAtLaunch()          // after a crash: ask to send the report (never typed text)
        if UserDefaults.standard.bool(forKey: "showOnboarding") { OnboardingWindow.show() }   // -showOnboarding YES (screenshots)
        if UserDefaults.standard.bool(forKey: "showAbout") { AboutPanel.show() }             // -showAbout YES (screenshots)
        if UserDefaults.standard.bool(forKey: "showMain") { Windows.main.show() }           // -showMain YES (screenshots)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forceDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }   // screenshots
        #endif
        if UserDefaults.standard.bool(forKey: "showEmoji") {                                 // -showEmoji YES [-emojiQuery horse] (screenshots)
            EmojiPicker.shared.open()
            if let q = UserDefaults.standard.string(forKey: "emojiQuery") { EmojiPicker.shared.model.setRaw(q) }
        }
        // Opened by the user (not at login, minutes after boot): show the main window.
        if AppState.shared.isRunning && ProcessInfo.processInfo.systemUptime > 180 && !UserDefaults.standard.bool(forKey: "noWindowAtLaunch") {
            Windows.main.show()
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            VikeyCore.frontmostAppChanged()
            MainActor.assumeIsolated { AppState.shared.frontAppChanged() }   // queue: .main
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            VikeyCore.activeSpaceChanged()
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            VikeyCore.stop()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.startIfPossible() }   // queue: .main
        }
        installStatusItem()
    }

    // MARK: - Menu bar item (macOS 12 backport of MenuBarExtra)

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
        NotificationCenter.default.addObserver(forName: .VikeyLanguageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    private func updateStatusIcon() {
        statusItem?.button?.image = MenuBarIcon.image(vietnamese: VikeyCore.language() == 1)
    }

    /// Rebuilds the menu from current state every time it is about to open,
    /// mirroring what MenuBarContent rendered in the SwiftUI version.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        MainActor.assumeIsolated {
            let state = AppState.shared
            if state.needsOnboarding {
                addMenuItem(menu, "Cấp quyền cho Vikey…", #selector(menuShowOnboarding))
                menu.addItem(.separator())
            }
            let hotkey = Hotkey(raw: UserDefaults.standard.object(forKey: PrefKey.hotkey) as? Int ?? Hotkey.defaultValue)
            let languageItem = addMenuItem(menu, "Tiếng Việt   \(hotkey.display)", #selector(menuToggleLanguage))
            languageItem.state = state.language == 1 ? .on : .off
            let autoItem = addMenuItem(menu, "Tự chuyển Anh/Việt", #selector(menuToggleAutoSwitch))
            autoItem.state = autoSwitchPreference() ? .on : .off
            let app = VikeyCore.frontAppName()
            if VikeyCore.frontAppIsExcluded() {
                addMenuItem(menu, "\(app): đã loại trừ", nil).isEnabled = false
            } else {
                let perAppItem = addMenuItem(menu, "Tự chuyển ở \(app)", #selector(menuTogglePerAppAutoSwitch))
                perAppItem.state = VikeyCore.autoSwitchEnabledForFrontApp() ? .on : .off
            }
            menu.addItem(.separator())
            addMenuItem(menu, "Mở Vikey…", #selector(menuShowMain)).keyEquivalent = ","
            menu.addItem(.separator())
            addMenuItem(menu, "Hướng dẫn…", #selector(menuShowOnboarding))
            addMenuItem(menu, "Gửi góp ý…", #selector(menuOpenFeedback))
            addMenuItem(menu, "Kiểm tra cập nhật…", #selector(menuCheckForUpdates))
            addMenuItem(menu, "Giới thiệu Vikey", #selector(menuShowAbout))
            addMenuItem(menu, "Thoát Vikey", #selector(menuQuit)).keyEquivalent = "q"
        }
    }

    @discardableResult
    private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func autoSwitchPreference() -> Bool {
        (UserDefaults.standard.object(forKey: PrefKey.autoSwitch) as? Int ?? 1) == 1
    }

    @objc private func menuToggleLanguage() {
        MainActor.assumeIsolated { AppState.shared.toggleLanguage() }
        updateStatusIcon()
    }

    @objc private func menuToggleAutoSwitch() {
        UserDefaults.standard.set(autoSwitchPreference() ? 0 : 1, forKey: PrefKey.autoSwitch)
        Preferences.apply()
    }

    @objc private func menuTogglePerAppAutoSwitch() {
        VikeyCore.setAutoSwitchForFrontApp(!VikeyCore.autoSwitchEnabledForFrontApp())
        MainActor.assumeIsolated { AppState.shared.frontAppChanged() }
    }

    @objc private func menuShowOnboarding() { MainActor.assumeIsolated { OnboardingWindow.show() } }
    @objc private func menuShowMain() { MainActor.assumeIsolated { Windows.main.show() } }
    @objc private func menuOpenFeedback() { Feedback.open() }
    @objc private func menuCheckForUpdates() { Updater.shared.checkForUpdates() }
    @objc private func menuShowAbout() { MainActor.assumeIsolated { AboutPanel.show() } }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    /// Opening Vikey again while it runs (Finder, Spotlight, Dock) shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppState.shared.needsOnboarding { OnboardingWindow.show() } else { Windows.main.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        VikeyCore.flushTypingLog()
    }
}
