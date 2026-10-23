import Foundation
import CoreGraphics
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

    func isPressed(flags: CGEventFlags) -> Bool {
        switch self {
        case .cmdR: return flags.contains(.maskCommand)
        case .altR: return flags.contains(.maskAlternate)
        case .ctrlR: return flags.contains(.maskControl)
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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkey: Hotkey = .cmdR
    private var isActive: Bool = true

    private var isRecording: Bool = false
    private var otherKeyPressed: Bool = false
    private let lock = NSLock()

    private init() {
        let saved = ConfigManager.shared.config.hotkey
        self.hotkey = Hotkey(rawValue: saved) ?? .cmdR
        self.isActive = ConfigManager.shared.config.active
    }

    func setHotkey(_ hotkey: Hotkey) {
        lock.lock()
        self.hotkey = hotkey
        lock.unlock()
    }

    func setActive(_ active: Bool) {
        lock.lock()
        self.isActive = active
        if !active && isRecording {
            isRecording = false
            delegate?.hotkeyDidCancelRecording()
        }
        lock.unlock()
    }

    static func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("[HotkeyManager] Failed to create CGEvent.tap. Check Accessibility permissions.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[HotkeyManager] Global hotkey tap installed successfully.")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
                self.runLoopSource = nil
            }
            self.eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        defer { lock.unlock() }

        guard isActive else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged {
            if keyCode == hotkey.keyCode {
                let pressed = hotkey.isPressed(flags: event.flags)
                if pressed && !isRecording {
                    // Start recording
                    isRecording = true
                    otherKeyPressed = false
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyDidStartRecording()
                    }
                } else if !pressed && isRecording {
                    // Release hotkey
                    isRecording = false
                    let cancelled = otherKeyPressed
                    DispatchQueue.main.async { [weak self] in
                        if cancelled {
                            self?.delegate?.hotkeyDidCancelRecording()
                        } else {
                            self?.delegate?.hotkeyDidStopRecording()
                        }
                    }
                }
            }
        } else if type == .keyDown {
            if isRecording && keyCode != hotkey.keyCode {
                // Another key was pressed during push-to-talk -> cancel on release
                otherKeyPressed = true
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
