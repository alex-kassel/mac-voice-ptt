import Foundation
import AppKit
import CoreGraphics

final class Paster {
    static let shared = Paster()

    private init() {}

    func paste(text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        // Write new text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Post synthetic Cmd+V
        postCmdV()

        // Restore clipboard history after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let prev = previousString {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
        }
    }

    private func postCmdV() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual key code for 'v'
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            NSLog("[Paster] Failed to create CGEvent for Cmd+V")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
