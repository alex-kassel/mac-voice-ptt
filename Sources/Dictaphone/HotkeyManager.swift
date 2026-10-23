import Foundation
import AppKit

enum Hotkey: String, CaseIterable {
    case cmdR = "cmd_r"
    case altR = "alt_r"
    case ctrlR = "ctrl_r"

    var title: String {
        switch self {
        case .cmdR: return "Right ⌘"
        case .altR: return "Right ⌥"
        case .ctrlR: return "Right ⌃"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .cmdR: return 54  // Right Command
        case .altR: return 61  // Right Option
        case .ctrlR: return 62  // Right Control
        }
    }

    func isPressed(event: NSEvent) -> Bool {
        switch self {
        case .cmdR: return event.modifierFlags.contains(.command)
        case .altR: return event.modifierFlags.contains(.option)
        case .ctrlR: return event.modifierFlags.contains(.control)
        }
    }
}

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidStartRecording()
    func hotkeyDidStopRecording()
    func hotkeyDidCancelRecording()
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    weak var delegate: HotkeyManagerDelegate?

    private var hotkey: Hotkey = .cmdR
    private var isActive: Bool = true

    private var isRecording: Bool = false
    private var otherKeyPressed: Bool = false
    private let lock = NSLock()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var permissionTimer: Timer?

    private init() {
        let saved = ConfigManager.shared.config.hotkey
        self.hotkey = Hotkey(rawValue: saved) ?? .cmdR
        self.isActive = ConfigManager.shared.config.active
    }

    func setHotkey(_ hotkey: Hotkey) {
        lock.lock()
        self.hotkey = hotkey
        Logger.log("[HotkeyManager] Active hotkey changed to: %@", hotkey.title)
        lock.unlock()
    }

    func setActive(_ active: Bool) {
        lock.lock()
        self.isActive = active
        Logger.log("[HotkeyManager] Active state changed to: %@", active ? "ENABLED" : "DISABLED")
        if !active && isRecording {
            isRecording = false
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidCancelRecording()
            }
        }
        lock.unlock()
    }

    static func isAccessibilityGranted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        if HotkeyManager.isAccessibilityGranted(prompt: false) {
            setupMonitors()
        } else {
            Logger.log("[HotkeyManager] Accessibility not granted yet. Starting permission watcher...")
            _ = HotkeyManager.isAccessibilityGranted(prompt: true)
            startPermissionWatcher()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        permissionTimer?.invalidate()
        permissionTimer = nil

        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
        Logger.log("[HotkeyManager] Monitors stopped.")
    }

    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if HotkeyManager.isAccessibilityGranted(prompt: false) {
                Logger.log("[HotkeyManager] Accessibility permission granted by user!")
                timer.invalidate()
                self.permissionTimer = nil
                self.lock.lock()
                self.setupMonitors()
                self.lock.unlock()
            }
        }
    }

    private func setupMonitors() {
        if globalMonitor != nil { return }

        Logger.log("[HotkeyManager] Registering global & local event monitors for hotkey: %@", hotkey.title)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        if globalMonitor != nil {
            Logger.log("[HotkeyManager] Global monitor successfully registered.")
        } else {
            Logger.log("[HotkeyManager] WARNING: Global monitor returned nil. Accessibility might still be blocked.")
        }
    }

    private func handleEvent(_ event: NSEvent) {
        lock.lock()
        defer { lock.unlock() }

        guard isActive else { return }

        let keyCode = Int64(event.keyCode)

        if event.type == .flagsChanged {
            if keyCode == hotkey.keyCode {
                let pressed = hotkey.isPressed(event: event)

                if pressed && !isRecording {
                    // Hotkey pressed down
                    isRecording = true
                    otherKeyPressed = false
                    Logger.log("[HotkeyManager] Hotkey PRESSED (%@, code %lld) -> START RECORDING", hotkey.title, keyCode)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyDidStartRecording()
                    }
                } else if !pressed && isRecording {
                    // Hotkey released
                    isRecording = false
                    let cancelled = otherKeyPressed
                    if cancelled {
                        Logger.log("[HotkeyManager] Hotkey RELEASED -> CANCELLED (other key was pressed)")
                        DispatchQueue.main.async { [weak self] in
                            self?.delegate?.hotkeyDidCancelRecording()
                        }
                    } else {
                        Logger.log("[HotkeyManager] Hotkey RELEASED -> STOP RECORDING (processing audio)")
                        DispatchQueue.main.async { [weak self] in
                            self?.delegate?.hotkeyDidStopRecording()
                        }
                    }
                }
            }
        } else if event.type == .keyDown {
            if isRecording && keyCode != hotkey.keyCode {
                Logger.log("[HotkeyManager] Other key pressed while recording (code %lld) -> will cancel on release", keyCode)
                otherKeyPressed = true
            }
        }
    }
}
