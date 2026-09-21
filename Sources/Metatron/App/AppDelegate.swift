import Foundation
import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public var statusItem: NSStatusItem?
    public var pillPanel: FloatingPillPanel?

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var watchdogTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as standard macOS application with Dock presence
        NSApp.setActivationPolicy(.regular)

        setupMainMenu()
        setupStatusItem()
        setupFloatingPill()

        // Start global keyboard and modifier listener
        HotkeyManager.shared.startListening()

        // Auto-launch local MLX daemon if local engine selected
        LocalDaemonClient.shared.ensureDaemonRunning()

        // Keep-alive watchdog timer
        startWatchdog()

        // Show permissions window on first launch if permissions not granted
        if !HotkeyManager.isAccessibilityGranted() || !AudioRecorder.shared.hasPermission {
            openPermissions()
        }
    }

    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { _ in
            Task { @MainActor in
                if AppState.shared.speechEngineType == .localMLX && !LocalDaemonClient.shared.isDaemonRunning() {
                    NSLog("[Metatron Watchdog] Daemon offline, auto-restarting...")
                    LocalDaemonClient.shared.ensureDaemonRunning()
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stopListening()
        pillPanel?.saveCurrentPosition()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pillPanel?.orderFront(nil)
        return true
    }

    private func setupFloatingPill() {
        let panel = FloatingPillPanel()
        panel.orderFront(nil)
        self.pillPanel = panel
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu (Metatron)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: "About Metatron", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "Permissions & Setup...", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        appMenu.addItem(permissionsItem)

        let historyItem = NSMenuItem(title: "Dictation History...", action: #selector(openHistory), keyEquivalent: "y")
        historyItem.target = self
        appMenu.addItem(historyItem)

        appMenu.addItem(NSMenuItem.separator())

        let servicesMenuItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesMenuItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesMenuItem)

        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "Hide Metatron", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Metatron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit Menu (crucial for copy/paste/select in input fields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Metatron")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Metatron Scribe", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let dictateItem = NSMenuItem(title: "Dictate (Hold Fn)", action: #selector(toggleDictation), keyEquivalent: "")
        dictateItem.target = self
        menu.addItem(dictateItem)

        let copyLastItem = NSMenuItem(title: "Copy Last Dictation", action: #selector(copyLastDictationAction), keyEquivalent: "c")
        copyLastItem.target = self
        menu.addItem(copyLastItem)

        // Transcription Style Submenu
        let styleMenuItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu()
        for style in TranscriptionStyle.allCases {
            let item = NSMenuItem(title: style.rawValue, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            styleSubmenu.addItem(item)
        }
        styleMenuItem.submenu = styleSubmenu
        menu.addItem(styleMenuItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "Dictation History...", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings & Vocabulary...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "Permissions & Setup...", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let centerPillItem = NSMenuItem(title: "Center Floating Pill", action: #selector(centerPill), keyEquivalent: "")
        centerPillItem.target = self
        menu.addItem(centerPillItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Metatron", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if let copyItem = menu.items.first(where: { $0.action == #selector(copyLastDictationAction) }) {
            let lastText = AppState.shared.lastTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if lastText.isEmpty {
                copyItem.title = "Copy Last Dictation (None)"
                copyItem.isEnabled = false
            } else {
                let preview = lastText.count > 25 ? String(lastText.prefix(22)) + "..." : lastText
                copyItem.title = "Copy: \"\(preview)\""
                copyItem.isEnabled = true
            }
        }
    }

    @objc private func toggleDictation() {
        AppState.shared.toggleRecording()
    }

    @objc private func copyLastDictationAction() {
        AppState.shared.copyLastDictation()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? TranscriptionStyle {
            AppState.shared.transcriptionStyle = style
        }
    }

    @objc public func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Metatron Settings"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openHistory() {
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Metatron History"
            window.center()
            window.contentView = NSHostingView(rootView: HistoryView())
            window.isReleasedWhenClosed = false
            self.historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openPermissions() {
        if permissionsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Metatron Permissions & Setup"
            window.center()
            window.contentView = NSHostingView(rootView: PermissionsView())
            window.isReleasedWhenClosed = false
            self.permissionsWindow = window
        }
        permissionsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func centerPill() {
        pillPanel?.resetPositionToCenter()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
