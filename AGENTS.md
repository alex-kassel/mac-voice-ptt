# AGENTS.MD — `mac-voice-ptt` (Dictaphone)

Push-to-Talk voice dictation tool for macOS powered by OpenAI's `gpt-4o-mini-transcribe`.

---

## 1. Architectural Overview

1. **Global Push-to-Talk Hotkey (`HotkeyManager.swift`)**:
   - Intercepts global modifier keys using `NSEvent.addGlobalMonitorForEvents` and `NSEvent.addLocalMonitorForEvents`.
   - Default hotkey: Right Command ⌘ (virtual key code `54`).
   - Accidental press protection: typing another key while holding the hotkey cancels recording upon release.
   - Dynamic permission watcher: monitors `AXIsProcessTrusted()` every 1.5s until granted.

2. **Audio Capture Pipeline (`AudioRecorder.swift`)**:
   - Captures Linear PCM 16-bit 16kHz Mono WAV via `AVFoundation.AVAudioRecorder`.
   - Temporary file in `FileManager.default.temporaryDirectory` (`/var/folders/.../T/dictaphone_<UUID>.wav`).
   - **Crucial Rule**: Audio files must be deleted immediately (`try? FileManager.default.removeItem(at: fileURL)`) after transcription completes or upon cancellation. Discards recordings shorter than 0.25s.

3. **Transcription & Auto-Paste (`Transcriber.swift`, `Paster.swift`)**:
   - Async `URLSession` multipart client calling OpenAI audio transcriptions endpoint.
   - Restores existing clipboard content after dispatching a synthetic `Cmd+V` keystroke via `CGEvent` to `kCGHIDEventTap`.

4. **Top-Right High-Contrast HUD Overlay (`OverlayPanel.swift`)**:
   - Subclass of `NSPanel` with style masks `[.borderless, .nonactivatingPanel]`.
   - **Never set `isFloatingPanel = true`**: in AppKit, `isFloatingPanel = true` internally resets window level back to 3 (`.floatingWindow`), hiding it behind active applications.
   - Explicitly configured with:
     ```swift
     self.level = NSWindow.Level(Int(CGWindowLevelForKey(.assistiveTechHighWindow))) // Layer 1500
     self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
     ```
   - Position: **Top-Right corner of the active display** (`visibleFrame.maxX - width - 20`, `visibleFrame.maxY - height - 20`), tracking the cursor display location (`NSEvent.mouseLocation`).
   - UI: High-contrast dark graphite container (`#1a1a1f`, 95% opacity, `darkAqua`), glowing red recording dot, and bold monospaced white timer (18pt bold) driven by a GCD `DispatchSourceTimer` on the main queue (`queue: .main`).

5. **Recent Transcriptions History Studio (`HistoryManager.swift`, `HistoryWindowController.swift`)**:
   - Stores recent transcriptions in `~/.dictaphone/history.json` (configurable max items, default 25).
   - **Top 10 Menu Quick Access**: Items 1–10 displayed directly in `Recent Transcriptions ▸` menu bar submenu with one-click copy.
   - **Order Rule**:
     - In the window and menu, items are sorted **newest first** (#1 is latest spoken).
     - Upon multi-selection (`Cmd+Click`, `Shift+Click`), `copyCombined` reverses the selection to natural chronological order (oldest to newest) and joins items with newline `\n` to assemble coherent prompts without manual re-ordering.
   - **Inline Editing & Deletion**: Cells allow inline text modifications auto-saved to `history.json` on edit end; single items can be removed via the `✕` button or Backspace/Delete key.

6. **Diagnostics & Logging (`Logger.swift`)**:
   - Writes to `~/.dictaphone/dictaphone.log` with automatic 2 MB log rotation.
   - Menu bar item **«Open Log File»** for instant inspection.
   - Each session is isolated with leading newline `\n` and quoted transcription previews.

7. **Documentation Maintenance (`README.md` & `AGENTS.md`)**:
   - Any new feature, shortcut, or architectural change MUST immediately be documented in `README.md` and this localized `AGENTS.md`. Never let docs fall out of sync with code.

---

## 2. Build & Test Commands

```bash
# Compile binary:
swift build --build-system native

# Build .app bundle:
bash scripts/build_app.sh

# Install into /Applications and launch:
bash scripts/install.sh

# Build DMG:
bash scripts/create_dmg.sh
```
