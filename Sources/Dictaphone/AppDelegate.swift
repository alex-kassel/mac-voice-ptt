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
        overlayPanel.hide()
        recorder.cancel()
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidStartRecording() {
        Logger.log("[AppDelegate] Starting audio recorder...")
        guard recorder.start() else {
            Logger.log("[AppDelegate] Failed to start audio recorder!")
            return
        }
        overlayPanel.show()
        menuBarController.setRecording(true)
    }

    func hotkeyDidStopRecording() {
        overlayPanel.hide()
        menuBarController.setRecording(false)

        guard let fileURL = recorder.stop() else {
            Logger.log("[AppDelegate] Recording stopped: audio discarded (too short or empty)")
            return
        }

        let language = ConfigManager.shared.config.language
        Logger.log("[AppDelegate] Audio captured at: %@. Requesting transcription (lang: %@)...", fileURL.path, language)

        Task {
            do {
                let text = try await transcriber.transcribe(fileURL: fileURL, language: language)
                try? FileManager.default.removeItem(at: fileURL)

                if !text.isEmpty {
                    Logger.log("[AppDelegate] Transcription success (%ld chars). Pasting...", text.count)
                    await MainActor.run {
                        Paster.shared.paste(text: text)
                    }
                } else {
                    Logger.log("[AppDelegate] Transcription returned empty text.")
                }
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                Logger.log("[AppDelegate] Transcription failed: %@", error.localizedDescription)
                await MainActor.run {
                    self.showErrorNotification(error.localizedDescription)
                }
            }
        }
    }

    func hotkeyDidCancelRecording() {
        Logger.log("[AppDelegate] Recording cancelled.")
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
        Logger.log("[AppDelegate] Language changed to: %@", language)
    }

    func menuBarDidRequestQuit() {
        Logger.log("[AppDelegate] Quit requested via menu bar.")
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
