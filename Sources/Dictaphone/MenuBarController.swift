import Foundation
import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidChangeActive(_ active: Bool)
    func menuBarDidChangeHotkey(_ hotkey: Hotkey)
    func menuBarDidChangeLanguage(_ language: String)
    func menuBarDidRequestQuit()
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    weak var delegate: MenuBarControllerDelegate?

    private var activeMenuItem: NSMenuItem!
    private var hotkeyMenu: NSMenu!
    private var languageMenu: NSMenu!
    private var launchAtLoginItem: NSMenuItem!

    override init() {
        super.init()
        setupStatusItem()
        buildMenu()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "◉"
            button.font = NSFont.systemFont(ofSize: 14.0, weight: .medium)
        }
        statusItem.menu = menu
        menu.delegate = self
    }

    func setRecording(_ recording: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button else { return }
            button.title = recording ? "●" : "◉"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh menu states when user clicks the menu bar item
        refreshMenuStates()
    }

    private func buildMenu() {
        menu.removeAllItems()

        // 1. Active toggle
        activeMenuItem = NSMenuItem(title: "Active", action: #selector(toggleActive), keyEquivalent: "")
        activeMenuItem.target = self
        menu.addItem(activeMenuItem)

        // 2. Hotkey submenu
        let hotkeyParent = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        hotkeyMenu = NSMenu(title: "Hotkey")
        for key in Hotkey.allCases {
            let item = NSMenuItem(title: key.title, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            hotkeyMenu.addItem(item)
        }
        hotkeyParent.submenu = hotkeyMenu
        menu.addItem(hotkeyParent)

        // 3. Language submenu
        let langParent = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageMenu = NSMenu(title: "Language")
        let languages = [
            ("auto", "Auto"),
            ("ru", "Русский"),
            ("de", "Deutsch"),
            ("en", "English")
        ]
        for (code, label) in languages {
            let item = NSMenuItem(title: label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            languageMenu.addItem(item)
        }
        langParent.submenu = languageMenu
        menu.addItem(langParent)

        menu.addItem(NSMenuItem.separator())

        // 4. Launch at Login
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        // 5. API Key prompt
        let apiKeyItem = NSMenuItem(title: "OpenAI API Key...", action: #selector(promptApiKey), keyEquivalent: "")
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(title: "Quit Dictaphone", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenuStates()
    }

    private func refreshMenuStates() {
        let config = ConfigManager.shared.config

        activeMenuItem.state = config.active ? .on : .off

        for item in hotkeyMenu.items {
            if let key = item.representedObject as? Hotkey {
                item.state = (key.rawValue == config.hotkey) ? .on : .off
            }
        }

        for item in languageMenu.items {
            if let code = item.representedObject as? String {
                item.state = (code == config.language) ? .on : .off
            }
        }

        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
    }

    @objc private func toggleActive() {
        let current = ConfigManager.shared.config.active
        let newActive = !current
        ConfigManager.shared.update(active: newActive)
        refreshMenuStates()
        delegate?.menuBarDidChangeActive(newActive)
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? Hotkey else { return }
        ConfigManager.shared.update(hotkey: key.rawValue)
        refreshMenuStates()
        delegate?.menuBarDidChangeHotkey(key)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        ConfigManager.shared.update(language: code)
        refreshMenuStates()
        delegate?.menuBarDidChangeLanguage(code)
    }

    @objc private func toggleLaunchAtLogin() {
        let current = LaunchAtLoginManager.shared.isEnabled
        let newState = !current
        _ = LaunchAtLoginManager.shared.setEnabled(newState)
        refreshMenuStates()
    }

    @objc private func promptApiKey() {
        let currentKey = ConfigManager.shared.getOpenAIKey() ?? ""
        let alert = NSAlert()
        alert.messageText = "OpenAI API Key"
        alert.informativeText = "Enter your OpenAI API key (starts with sk-):"
        alert.alertStyle = .informational

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = currentKey
        alert.accessoryView = input

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newKey = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            ConfigManager.shared.update(apiKey: newKey)
        }
    }

    @objc private func quitApp() {
        delegate?.menuBarDidRequestQuit()
    }
}
