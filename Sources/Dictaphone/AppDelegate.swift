import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate, MenuBarControllerDelegate {
    private var menuBarController: MenuBarController!
    private var overlayPanel: OverlayPanel!
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background menu bar accessory (no Dock icon, no App Switcher)
        NSApp.setActivationPolicy(.accessory)

        // Disable macOS automatic app termination/sleep for menu bar app
        ProcessInfo.processInfo.disableAutomaticTermination("Dictaphone background push-to-talk listener")

        Logger.log("[AppDelegate] Starting Dictaphone...")

        // Setup standard Edit menu for Cmd+C / Cmd+V in accessory app dialogs
        setupMainMenu()

        // Initialize UI
        menuBarController = MenuBarController()
        menuBarController.delegate = self
        overlayPanel = OverlayPanel()

        // Setup hotkey listener
        let hotkeyManager = HotkeyManager.shared
        hotkeyManager.delegate = self

        // Check Microphone permission
        AudioRecorder.checkMicrophonePermission { granted in
            Logger.log("[AppDelegate] Microphone permission: %@", granted ? "AUTHORIZED" : "DENIED")
        }

        hotkeyManager.start()
        Logger.log("[AppDelegate] Dictaphone initialized and ready.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("[AppDelegate] Application terminating...")
        HotkeyManager.shared.stop()
        overlayPanel.hideImmediate()
        recorder.cancel()
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidStartRecording() {
        let hotkeyTitle = Hotkey(rawValue: ConfigManager.shared.config.hotkey)?.title ?? "Right ⌘"
        Logger.startSession(hotkey: hotkeyTitle)
        guard recorder.start() else {
            Logger.endSessionError(error: "Failed to initialize and start audio input stream.")
            return
        }
        overlayPanel.showRecording()
        menuBarController.setRecording(true)
    }

    func hotkeyDidStopRecording() {
        menuBarController.setRecording(false)

        guard let fileURL = recorder.stop() else {
            overlayPanel.hideImmediate()
            Logger.endSessionSilent()
            return
        }

        let language = ConfigManager.shared.config.language
        let duration = recorder.lastDuration
        Logger.log("[AudioRecorder] Audio captured (file: %@, duration: %.1fs). Requesting transcription (lang: %@)...", fileURL.lastPathComponent, duration, language)

        // Keep HUD visible and transition smoothly to processing mode
        overlayPanel.showProcessing()
        menuBarController.setTranscribing(true)

        Task {
            do {
                let text = try await transcriber.transcribe(fileURL: fileURL, language: language)
                try? FileManager.default.removeItem(at: fileURL)

                await MainActor.run {
                    self.menuBarController.setTranscribing(false)
                }

                if !text.isEmpty {
                    HistoryManager.shared.add(text: text)
                    Logger.endSessionSuccess(text: text, charsCount: text.count)
                    await MainActor.run {
                        self.overlayPanel.showSuccess {
                            Paster.shared.paste(text: text)
                        }
                    }
                } else {
                    await MainActor.run {
                        self.overlayPanel.hideImmediate()
                    }
                    Logger.endSessionSilent()
                }
            } catch {
                // Preserve audio in recovery cache instead of deleting
                RecoveryManager.shared.saveFailedAudio(
                    from: fileURL,
                    language: language,
                    duration: duration,
                    error: error.localizedDescription
                )

                Logger.endSessionError(error: error.localizedDescription)
                await MainActor.run {
                    self.overlayPanel.hideImmediate()
                    self.menuBarController.setTranscribing(false)
                    self.menuBarController.updateRetryState()
                    self.showErrorNotification(error.localizedDescription)
                }
            }
        }
    }

    func hotkeyDidCancelRecording() {
        overlayPanel.hideImmediate()
        menuBarController.setRecording(false)
        recorder.cancel()
        Logger.endSessionCancelled(reason: "Cancelled by user (other key pressed or deactivated)")
    }

    // MARK: - MenuBarControllerDelegate

    func menuBarDidChangeActive(_ active: Bool) {
        HotkeyManager.shared.setActive(active)
    }

    func menuBarDidChangeHotkey(_ hotkey: Hotkey) {
        HotkeyManager.shared.setHotkey(hotkey)
    }

    func menuBarDidChangeLanguage(_ language: String) {
        Logger.log("[AppDelegate] Language changed to: %@", language)
    }

    func menuBarDidChangeModel(_ model: String) {
        Logger.log("[AppDelegate] Transcription model changed to: %@", model)
    }

    func menuBarDidRequestRetry() {
        retryLastTranscription()
    }

    func menuBarDidRequestQuit() {
        Logger.log("[AppDelegate] Quit requested via menu bar.")
        NSApp.terminate(nil)
    }

    // MARK: - Retry Logic

    func retryLastTranscription() {
        guard let failedInfo = RecoveryManager.shared.getLastFailedAudioInfo() else {
            Logger.log("[AppDelegate] Retry requested, but no failed dictation found in recovery cache.")
            return
        }

        Logger.log("[AppDelegate] Retrying failed dictation (duration: %.1fs, file: %@)...", failedInfo.duration, failedInfo.url.lastPathComponent)
        overlayPanel.showProcessing()
        menuBarController.setTranscribing(true)

        Task {
            do {
                let text = try await transcriber.transcribe(fileURL: failedInfo.url, language: failedInfo.language)
                RecoveryManager.shared.clearFailedAudio()

                await MainActor.run {
                    self.menuBarController.setTranscribing(false)
                    self.menuBarController.updateRetryState()
                }

                if !text.isEmpty {
                    HistoryManager.shared.add(text: text)
                    Logger.endSessionSuccess(text: text, charsCount: text.count)
                    await MainActor.run {
                        self.overlayPanel.showSuccess {
                            Paster.shared.paste(text: text)
                        }
                    }
                } else {
                    await MainActor.run {
                        self.overlayPanel.hideImmediate()
                    }
                    Logger.endSessionSilent()
                }
            } catch {
                Logger.log("[AppDelegate] Retry transcription failed: %@", error.localizedDescription)
                await MainActor.run {
                    self.overlayPanel.hideImmediate()
                    self.menuBarController.setTranscribing(false)
                    self.menuBarController.updateRetryState()
                    self.showErrorNotification(error.localizedDescription)
                }
            }
        }
    }

    private func showErrorNotification(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Dictaphone"
        if let failedInfo = RecoveryManager.shared.getLastFailedAudioInfo() {
            let durStr = failedInfo.duration > 0 ? String(format: " (%.0f сек)", failedInfo.duration) : ""
            alert.informativeText = "Ошибка сети: \(message)\n\nВаша голосовая запись\(durStr) надёжно сохранена! Вы можете повторить отправку прямо сейчас или позже через меню Dictaphone (или Cmd+Shift+R)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Повторить сейчас")
            alert.addButton(withTitle: "Оставить в меню")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.retryLastTranscription()
            }
        } else {
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Dictaphone")
        let prefItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        appMenu.addItem(prefItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Dictaphone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showPreferences()
    }
}
