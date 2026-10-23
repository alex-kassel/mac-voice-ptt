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

        // Initialize UI
        menuBarController = MenuBarController()
        menuBarController.delegate = self
        overlayPanel = OverlayPanel()

        // Setup hotkey listener
        let hotkeyManager = HotkeyManager.shared
        hotkeyManager.delegate = self

        // Check Accessibility permission
        if !HotkeyManager.checkAccessibilityPermission(prompt: false) {
            NSLog("[AppDelegate] Accessibility permission not granted yet. Prompting user...")
            _ = HotkeyManager.checkAccessibilityPermission(prompt: true)
        }

        // Check Microphone permission
        AudioRecorder.checkMicrophonePermission { granted in
            if !granted {
                NSLog("[AppDelegate] Microphone permission denied or restricted.")
            }
        }

        hotkeyManager.start()
        NSLog("[AppDelegate] Dictaphone initialized and running.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        overlayPanel.hide()
        recorder.cancel()
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidStartRecording() {
        guard recorder.start() else {
            NSLog("[AppDelegate] Failed to start audio recording.")
            return
        }
        overlayPanel.show()
        menuBarController.setRecording(true)
    }

    func hotkeyDidStopRecording() {
        overlayPanel.hide()
        menuBarController.setRecording(false)

        guard let fileURL = recorder.stop() else {
            return
        }

        let language = ConfigManager.shared.config.language

        Task {
            do {
                let text = try await transcriber.transcribe(fileURL: fileURL, language: language)
                try? FileManager.default.removeItem(at: fileURL)

                if !text.isEmpty {
                    await MainActor.run {
                        Paster.shared.paste(text: text)
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                NSLog("[AppDelegate] Transcription error: %@", error.localizedDescription)
                await MainActor.run {
                    self.showErrorNotification(error.localizedDescription)
                }
            }
        }
    }

    func hotkeyDidCancelRecording() {
        overlayPanel.hide()
        menuBarController.setRecording(false)
        recorder.cancel()
    }

    // MARK: - MenuBarControllerDelegate

    func menuBarDidChangeActive(_ active: Bool) {
        HotkeyManager.shared.setActive(active)
    }

    func menuBarDidChangeHotkey(_ hotkey: Hotkey) {
        HotkeyManager.shared.setHotkey(hotkey)
    }

    func menuBarDidChangeLanguage(_ language: String) {
        // Saved in ConfigManager
    }

    func menuBarDidRequestQuit() {
        NSApp.terminate(nil)
    }

    private func showErrorNotification(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Dictaphone"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
