import Foundation
import AppKit

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var hotkeyPopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var modelPopUp: NSPopUpButton!
    private var apiKeyField: NSSecureTextField!
    private var showApiKeyBtn: NSButton!
    private var apiKeyVisibleField: NSTextField!

    private var maxHistoryField: NSTextField!
    private var maxHistoryStepper: NSStepper!
    private var focusModePopUp: NSPopUpButton!

    private var launchAtLoginCheckbox: NSButton!
    private var activeCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictaphone Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)

        setupUI()
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        var y: CGFloat = 450.0
        let labelX: CGFloat = 24.0
        let fieldX: CGFloat = 180.0
        let fieldWidth: CGFloat = 280.0

        // 1. Hotkey
        let hotkeyLabel = createLabel(text: "Push-to-Talk Hotkey:", x: labelX, y: y)
        contentView.addSubview(hotkeyLabel)

        hotkeyPopUp = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 4, width: fieldWidth, height: 26), pullsDown: false)
        for k in Hotkey.allCases {
            hotkeyPopUp.addItem(withTitle: k.title)
            hotkeyPopUp.lastItem?.representedObject = k
        }
        hotkeyPopUp.target = self
        hotkeyPopUp.action = #selector(hotkeyChanged)
        contentView.addSubview(hotkeyPopUp)

        // 2. Language
        y -= 40
        let langLabel = createLabel(text: "Speech Language:", x: labelX, y: y)
        contentView.addSubview(langLabel)

        languagePopUp = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 4, width: fieldWidth, height: 26), pullsDown: false)
        let languages: [(code: String, name: String)] = [
            ("auto", "Auto-detect (RU, DE, EN)"),
            ("ru", "Russian (Русский)"),
            ("de", "German (Deutsch)"),
            ("en", "English")
        ]
        for l in languages {
            languagePopUp.addItem(withTitle: l.name)
            languagePopUp.lastItem?.representedObject = l.code
        }
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)
        contentView.addSubview(languagePopUp)

        // 2b. AI Model
        y -= 40
        let modelLabel = createLabel(text: "AI Transcription Model:", x: labelX, y: y)
        contentView.addSubview(modelLabel)

        modelPopUp = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 4, width: fieldWidth, height: 26), pullsDown: false)
        let models: [(id: String, name: String)] = [
            ("whisper-1", "Whisper (whisper-1) — Fastest ($0.006/min)"),
            ("gpt-4o-mini-transcribe", "GPT-4o Mini Transcribe ($0.003/min)"),
            ("gpt-4o-transcribe", "GPT-4o Transcribe ($0.006/min)")
        ]
        for m in models {
            modelPopUp.addItem(withTitle: m.name)
            modelPopUp.lastItem?.representedObject = m.id
        }
        modelPopUp.target = self
        modelPopUp.action = #selector(modelChanged)
        contentView.addSubview(modelPopUp)

        // 3. OpenAI API Key
        y -= 40
        let apiLabel = createLabel(text: "OpenAI API Key:", x: labelX, y: y)
        contentView.addSubview(apiLabel)

        let keyFieldWidth: CGFloat = 210.0
        apiKeyField = NSSecureTextField(frame: NSRect(x: fieldX, y: y - 2, width: keyFieldWidth, height: 22))
        apiKeyField.placeholderString = "sk-..."
        contentView.addSubview(apiKeyField)

        apiKeyVisibleField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: keyFieldWidth, height: 22))
        apiKeyVisibleField.placeholderString = "sk-..."
        apiKeyVisibleField.isHidden = true
        contentView.addSubview(apiKeyVisibleField)

        showApiKeyBtn = NSButton(title: "Show", target: self, action: #selector(toggleShowApiKey))
        showApiKeyBtn.frame = NSRect(x: fieldX + keyFieldWidth + 6, y: y - 4, width: 64, height: 25)
        showApiKeyBtn.bezelStyle = .rounded
        contentView.addSubview(showApiKeyBtn)

        // Separator
        y -= 30
        let sep1 = NSBox(frame: NSRect(x: 24, y: y, width: 452, height: 1))
        sep1.boxType = .separator
        contentView.addSubview(sep1)

        // 4. Max History Items
        y -= 34
        let historyLabel = createLabel(text: "Max Saved History:", x: labelX, y: y)
        contentView.addSubview(historyLabel)

        maxHistoryField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: 55, height: 22))
        maxHistoryField.font = NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .regular)
        maxHistoryField.isEditable = false
        contentView.addSubview(maxHistoryField)

        maxHistoryStepper = NSStepper(frame: NSRect(x: fieldX + 60, y: y - 4, width: 19, height: 24))
        maxHistoryStepper.minValue = 5
        maxHistoryStepper.maxValue = 200
        maxHistoryStepper.increment = 5
        maxHistoryStepper.valueWraps = false
        maxHistoryStepper.target = self
        maxHistoryStepper.action = #selector(stepperChanged)
        contentView.addSubview(maxHistoryStepper)

        let itemsNote = createLabel(text: "entries (range: 5–200)", x: fieldX + 85, y: y)
        itemsNote.textColor = .secondaryLabelColor
        contentView.addSubview(itemsNote)

        // 5. On Window Open Focus Mode
        y -= 40
        let focusLabel = createLabel(text: "On History Window Open:", x: labelX, y: y)
        contentView.addSubview(focusLabel)

        focusModePopUp = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 4, width: fieldWidth, height: 26), pullsDown: false)
        for mode in HistoryFocusMode.allCases {
            focusModePopUp.addItem(withTitle: mode.title)
            focusModePopUp.lastItem?.representedObject = mode.rawValue
        }
        focusModePopUp.target = self
        focusModePopUp.action = #selector(focusModeChanged)
        contentView.addSubview(focusModePopUp)

        // Separator
        y -= 30
        let sep2 = NSBox(frame: NSRect(x: 24, y: y, width: 452, height: 1))
        sep2.boxType = .separator
        contentView.addSubview(sep2)

        // 6. Launch at Login
        y -= 34
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch Dictaphone automatically at login", target: self, action: #selector(launchAtLoginToggled))
        launchAtLoginCheckbox.frame = NSRect(x: labelX, y: y, width: 440, height: 20)
        contentView.addSubview(launchAtLoginCheckbox)

        // 7. Active Daemon Checkbox
        y -= 30
        activeCheckbox = NSButton(checkboxWithTitle: "Active (Listen to Push-to-Talk hotkeys in background)", target: self, action: #selector(activeToggled))
        activeCheckbox.frame = NSRect(x: labelX, y: y, width: 440, height: 20)
        contentView.addSubview(activeCheckbox)

        // Bottom Bar: Version & Done button
        let bottomY: CGFloat = 16.0
        let versionLabel = createLabel(text: "Dictaphone v1.3.0 • Native macOS Swift • Multi-Model", x: 24.0, y: bottomY + 4)
        versionLabel.font = NSFont.systemFont(ofSize: 11.0)
        versionLabel.textColor = .tertiaryLabelColor
        contentView.addSubview(versionLabel)

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        doneBtn.frame = NSRect(x: 400, y: bottomY, width: 76, height: 28)
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        contentView.addSubview(doneBtn)
    }

    func showPreferences() {
        populateFields()
        if let window = self.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func populateFields() {
        let config = ConfigManager.shared.config

        // Hotkey
        let hotkeyIdx = hotkeyPopUp.indexOfItem(withRepresentedObject: Hotkey(rawValue: config.hotkey) ?? .cmdR)
        if hotkeyIdx >= 0 {
            hotkeyPopUp.selectItem(at: hotkeyIdx)
        }

        // Language
        let langIndex = languagePopUp.itemArray.firstIndex { ($0.representedObject as? String) == config.language } ?? 0
        languagePopUp.selectItem(at: langIndex)

        // Model
        let modelIndex = modelPopUp.itemArray.firstIndex { ($0.representedObject as? String) == config.model } ?? 0
        modelPopUp.selectItem(at: modelIndex)

        // API Key
        let key = ConfigManager.shared.getOpenAIKey() ?? ""
        apiKeyField.stringValue = key
        apiKeyVisibleField.stringValue = key

        // Max history
        maxHistoryField.stringValue = "\(config.maxHistoryItems)"
        maxHistoryStepper.integerValue = config.maxHistoryItems

        // Focus mode
        let focusIndex = focusModePopUp.itemArray.firstIndex { ($0.representedObject as? String) == config.historyFocusMode } ?? 0
        focusModePopUp.selectItem(at: focusIndex)

        // System checkboxes
        launchAtLoginCheckbox.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        activeCheckbox.state = config.active ? .on : .off
    }

    @objc private func hotkeyChanged() {
        guard let key = hotkeyPopUp.selectedItem?.representedObject as? Hotkey else { return }
        ConfigManager.shared.update(hotkey: key.rawValue)
        HotkeyManager.shared.setHotkey(key)
    }

    @objc private func languageChanged() {
        guard let code = languagePopUp.selectedItem?.representedObject as? String else { return }
        ConfigManager.shared.update(language: code)
    }

    @objc private func modelChanged() {
        guard let modelId = modelPopUp.selectedItem?.representedObject as? String else { return }
        ConfigManager.shared.update(model: modelId)
    }

    @objc private func toggleShowApiKey() {
        let isShowing = !apiKeyVisibleField.isHidden
        if isShowing {
            // Hide
            apiKeyField.stringValue = apiKeyVisibleField.stringValue
            apiKeyVisibleField.isHidden = true
            apiKeyField.isHidden = false
            showApiKeyBtn.title = "Show"
        } else {
            // Show
            apiKeyVisibleField.stringValue = apiKeyField.stringValue
            apiKeyField.isHidden = true
            apiKeyVisibleField.isHidden = false
            showApiKeyBtn.title = "Hide"
        }
    }

    @objc private func stepperChanged() {
        let val = maxHistoryStepper.integerValue
        maxHistoryField.stringValue = "\(val)"
        ConfigManager.shared.update(maxHistoryItems: val)
    }

    @objc private func focusModeChanged() {
        guard let modeStr = focusModePopUp.selectedItem?.representedObject as? String else { return }
        ConfigManager.shared.update(historyFocusMode: modeStr)
    }

    @objc private func launchAtLoginToggled() {
        let enabled = launchAtLoginCheckbox.state == .on
        _ = LaunchAtLoginManager.shared.setEnabled(enabled)
    }

    @objc private func activeToggled() {
        let active = activeCheckbox.state == .on
        ConfigManager.shared.update(active: active)
        HotkeyManager.shared.setActive(active)
    }

    @objc private func doneClicked() {
        // Save API key if changed
        let key = apiKeyVisibleField.isHidden ? apiKeyField.stringValue : apiKeyVisibleField.stringValue
        ConfigManager.shared.update(apiKey: key)

        window?.close()
    }

    private func createLabel(text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 170, height: 20)
        label.font = NSFont.systemFont(ofSize: 13.0)
        label.alignment = .left
        return label
    }
}
