import Foundation
import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidChangeActive(_ active: Bool)
    func menuBarDidChangeHotkey(_ hotkey: Hotkey)
    func menuBarDidChangeLanguage(_ language: String)
    func menuBarDidChangeModel(_ model: String)
    func menuBarDidRequestRetry()
    func menuBarDidRequestQuit()
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    weak var delegate: MenuBarControllerDelegate?

    private var activeMenuItem: NSMenuItem!
    private var retryMenuItem: NSMenuItem!
    private var hotkeyMenu: NSMenu!
    private var languageMenu: NSMenu!
    private var modelMenu: NSMenu!
    private var historyMenu: NSMenu!
    private var launchAtLoginItem: NSMenuItem!

    private var isRecording = false
    private var isTranscribing = false

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
            guard let self = self else { return }
            self.isRecording = recording
            self.updateStatusButtonTitle()
        }
    }

    func setTranscribing(_ transcribing: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isTranscribing = transcribing
            self.updateStatusButtonTitle()
        }
    }

    private func updateStatusButtonTitle() {
        guard let button = statusItem.button else { return }
        if isRecording {
            button.title = "●"
        } else if isTranscribing {
            button.title = "◌"
        } else {
            button.title = "◉"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuStates()
    }

    private func buildMenu() {
        menu.removeAllItems()

        // 1. Active toggle
        activeMenuItem = NSMenuItem(title: "Active", action: #selector(toggleActive), keyEquivalent: "")
        activeMenuItem.target = self
        menu.addItem(activeMenuItem)

        // 1b. Retry Last Dictation (Shift+Cmd+R)
        retryMenuItem = NSMenuItem(title: "Retry Last Dictation", action: #selector(retryLastDictation), keyEquivalent: "R")
        retryMenuItem.keyEquivalentModifierMask = [.command, .shift]
        retryMenuItem.target = self
        menu.addItem(retryMenuItem)

        // 2. Recent Transcriptions (History) Submenu
        let historyParent = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
        historyMenu = NSMenu(title: "Recent Transcriptions")
        historyParent.submenu = historyMenu
        menu.addItem(historyParent)

        menu.addItem(NSMenuItem.separator())

        // 3. Hotkey submenu
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

        // 4. Language submenu
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

        // 4b. Model submenu
        let modelParent = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelMenu = NSMenu(title: "Model")
        let models = [
            ("whisper-1", "Whisper (Fastest, $0.006/min)"),
            ("gpt-4o-mini-transcribe", "GPT-4o Mini Transcribe ($0.003/min)"),
            ("gpt-4o-transcribe", "GPT-4o Transcribe ($0.006/min)")
        ]
        for (id, label) in models {
            let item = NSMenuItem(title: label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            modelMenu.addItem(item)
        }
        modelParent.submenu = modelMenu
        menu.addItem(modelParent)

        menu.addItem(NSMenuItem.separator())

        // 5. Preferences Window
        let prefItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)

        // 6. Launch at Login
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        // 7. OpenAI API Key
        let apiKeyItem = NSMenuItem(title: "OpenAI API Key...", action: #selector(promptApiKey), keyEquivalent: "")
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)

        // 8. Open Log File
        let logItem = NSMenuItem(title: "Open Log File", action: #selector(openLogFile), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        // 9. Quit
        let quitItem = NSMenuItem(title: "Quit Dictaphone", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenuStates()
    }

    func updateRetryState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let failedInfo = RecoveryManager.shared.getLastFailedAudioInfo() {
                let durStr = failedInfo.duration > 0 ? String(format: " (%.0fs)", failedInfo.duration) : ""
                self.retryMenuItem.title = "Retry Last Dictation\(durStr)"
                self.retryMenuItem.isEnabled = true
            } else {
                self.retryMenuItem.title = "Retry Last Dictation"
                self.retryMenuItem.isEnabled = false
            }
        }
    }

    private func refreshMenuStates() {
        let config = ConfigManager.shared.config

        activeMenuItem.state = config.active ? .on : .off
        updateRetryState()

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

        for item in modelMenu.items {
            if let id = item.representedObject as? String {
                item.state = (id == config.model) ? .on : .off
            }
        }

        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off

        // Refresh Recent Transcriptions Submenu
        historyMenu.removeAllItems()
        let history = HistoryManager.shared.getHistory()

        // 1. Show All History Window action
        let showAllItem = NSMenuItem(title: "Show All History (\(history.count))...", action: #selector(openHistoryWindow), keyEquivalent: "h")
        showAllItem.target = self
        historyMenu.addItem(showAllItem)
        historyMenu.addItem(NSMenuItem.separator())

        if history.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Transcriptions", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            // Show up to the first 10 items directly in menu for fast access
            let displayCount = min(history.count, 10)
            for idx in 0..<displayCount {
                let text = history[idx]
                let preview = text.count > 48 ? String(text.prefix(48)) + "..." : text
                let item = NSMenuItem(title: "\(idx + 1). \(preview)", action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = idx
                item.toolTip = text
                historyMenu.addItem(item)
            }
            historyMenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }
    }

    @objc private func retryLastDictation() {
        delegate?.menuBarDidRequestRetry()
    }

    @objc private func openHistoryWindow() {
        HistoryWindowController.shared.showHistory()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showPreferences()
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        _ = HistoryManager.shared.copyToClipboard(index: index)
    }

    @objc private func clearHistory() {
        HistoryManager.shared.clear()
        refreshMenuStates()
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

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        ConfigManager.shared.update(model: modelId)
        refreshMenuStates()
        delegate?.menuBarDidChangeModel(modelId)
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

    @objc private func openLogFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logUrl = home.appendingPathComponent(".dictaphone/dictaphone.log")
        NSWorkspace.shared.open(logUrl)
    }

    @objc private func quitApp() {
        delegate?.menuBarDidRequestQuit()
    }
}
