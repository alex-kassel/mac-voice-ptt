# AGENTS.MD — `mac-voice-ptt` (Dictaphone)

Push-to-Talk voice dictation tool for macOS powered by OpenAI (`whisper-1` by default, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe`).

---

## 1. Architectural Overview

1. **Global Push-to-Talk Hotkey (`HotkeyManager.swift`)**:
   - Intercepts global modifier keys using `NSEvent.addGlobalMonitorForEvents` and `NSEvent.addLocalMonitorForEvents`.
   - Default hotkey: Right Command ⌘ (virtual key code `54`).
   - Accidental press protection: typing another key while holding the hotkey cancels recording upon release.
   - Dynamic permission watcher: monitors `AXIsProcessTrusted()` every 1.5s until granted.

2. **Audio Capture Pipeline (`AudioRecorder.swift`)**:
   - Captures ultra-compact AAC 16kHz Mono 32kbps (`.m4a`) via `AVFoundation.AVAudioRecorder` with automatic fallback to Linear PCM 16-bit 16kHz Mono WAV (`.wav`).
   - Temporary file in `FileManager.default.temporaryDirectory` (`/var/folders/.../T/dictaphone_<UUID>.m4a`).
   - Cuts network upload payload by ~8x compared to uncompressed WAV (~160 KB vs ~1.3 MB for 40s of voice).
   - Audio files are deleted immediately after transcription completes or upon user cancellation. Discards recordings shorter than 0.25s.

3. **Transcription & Auto-Paste (`Transcriber.swift`, `Paster.swift`)**:
   - Async `URLSession` multipart client calling OpenAI audio transcriptions endpoint.
   - Configurable models: `whisper-1` (default, ~3x faster, $0.006/min), `gpt-4o-mini-transcribe` ($0.003/min), and `gpt-4o-transcribe` ($0.006/min).
   - Built-in automatic retry engine (up to 3 attempts with exponential backoff) for transient network drops (`NSURLErrorNetworkConnectionLost`, `-1005`, timeouts, and HTTP 5xx/429).
   - Re-creates URLSession connection pool upon socket disconnection to prevent Cloudflare/OpenAI idle keep-alive stale drops.
   - Restores existing clipboard content after dispatching a synthetic `Cmd+V` keystroke via `CGEvent` to `kCGHIDEventTap`.

4. **Zero Data Loss Recovery Engine (`RecoveryManager.swift`)**:
   - On network failure (after all retries exhaust), audio is NEVER deleted.
   - Moves failed audio into `~/.dictaphone/recovery/last_failed.m4a` along with duration, language, and error metadata.
   - Menu bar item **«Retry Last Dictation (Xs)»** (`⇧⌘R`) and informative macOS alert dialog allow instant one-click re-transcription and auto-paste once connectivity restores.

5. **Top-Right High-Contrast HUD Overlay (`OverlayPanel.swift`)**:
   - Subclass of `NSPanel` with style masks `[.borderless, .nonactivatingPanel]`.
   - **Never set `isFloatingPanel = true`**: in AppKit, `isFloatingPanel = true` internally resets window level back to 3 (`.floatingWindow`), hiding it behind active applications.
   - Explicitly configured with:
     ```swift
     self.level = NSWindow.Level(Int(CGWindowLevelForKey(.assistiveTechHighWindow))) // Layer 1500
     self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
     ```
   - Position: **Top-Right corner of the focused display** (`NSScreen.main`, fallback to mouse cursor screen), tracking active window keyboard focus across all Full-Screen apps and Spaces.
   - **Continuous 3-Stage Feedback Loop**:
     - *Recording*: Glowing red dot + active monospaced elapsed timer (`● 00:05`).
     - *Processing*: Keeps HUD visible on key release; switches to pulsing cyan indicator with `Processing…`.
     - *Success*: Flashes green checkmark `Done ✓` for 350ms before fading out, executing synthetic paste.

6. **Recent Transcriptions History Studio (`HistoryManager.swift`, `HistoryWindowController.swift`)**:
   - Stores recent transcriptions in `~/.dictaphone/history.json` (configurable max items, default 25).
   - **Top 10 Menu Quick Access**: Items 1–10 displayed directly in `Recent Transcriptions ▸` menu bar submenu with one-click copy.
   - **Order Rule**:
     - In the window and menu, items are sorted **newest first** (#1 is latest spoken).
     - Upon multi-selection (`Cmd+Click`, `Shift+Click`), `copyCombined` reverses the selection to natural chronological order (oldest to newest) and joins items with newline `\n` to assemble coherent prompts without manual re-ordering.
   - **Dynamic Table Row Heights & Baseline Alignment**:
     - Unselected rows are collapsed to a single line (38pt height), with row number, text field, and delete button `✕` vertically centered on the exact same baseline.
     - Selected rows (`isRowSelected(row)`) dynamically expand via `tableView(_:heightOfRow:)` and `noteHeightOfRows` to display the entire multi-line text with word wrapping. Double-clicking or clicking into the text allows editing the full multi-line text inline.
     - Unselected rows collapse back to single line with tail truncation (`...`).
   - For user-facing feature overviews, refer directly to `README.md`.

7. **Diagnostics & Logging (`Logger.swift`)**:
   - Writes to `~/.dictaphone/dictaphone.log` with automatic 2 MB log rotation.
   - Menu bar item **«Open Log File»** for instant inspection.
   - Each session is isolated with leading newline `\n` and quoted transcription previews.

8. **Release Policy**:
   - Always ask the user for confirmation before creating GitHub releases or tagging new versions. Do not create releases automatically on minor commits.

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
