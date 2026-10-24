# Dictaphone — Push-to-Talk Voice Transcription for macOS

**Dictaphone** is a native, lightweight macOS push-to-talk voice transcription utility. Hold down a configurable modifier key (by default, Right Command ⌘), speak into your microphone, and release: your speech is transcribed via OpenAI's `gpt-4o-mini-transcribe` and instantly typed/pasted at your current cursor position.

Built completely in **Swift** with **zero external dependencies**, relying exclusively on native macOS frameworks (`AppKit`, `AVFoundation`, `CoreGraphics`, `ServiceManagement`, `Foundation`).

[![Download DMG](https://img.shields.io/badge/Download-Dictaphone.dmg-blue?style=for-the-badge&logo=apple)](https://github.com/alex-kassel/mac-voice-ptt/releases/latest/download/Dictaphone.dmg)
[![macOS](https://img.shields.io/badge/macOS-13.0+-black?style=for-the-badge&logo=apple)](https://github.com/alex-kassel/mac-voice-ptt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

---

## Highlights

- **Ultra-lightweight**: App bundle is **~280 KB** (compared to ~150+ MB for Python + virtualenv).
- **Minimal memory footprint**: Runs quietly in the menu bar consuming **~15–25 MB RAM** (vs 120+ MB for Python).
- **Transcriptions History Studio (`Cmd+H`)**: Native dedicated window featuring dynamic row expansion on click, inline editing, multi-select prompt stitching, and tactile copy confirmation.
- **Dedicated Preferences Window (`Cmd+,`)**: Native settings modal to customize hotkeys, languages, OpenAI API keys, history capacity, and window opening focus behavior.
- **High-Contrast Top-Right HUD**: Monospaced elapsed timer with glowing pulsing dot rendered in a dark graphite pill, guaranteed visible over light and dark themes and across all full-screen spaces.
- **Zero latency**: Native Cocoa run loop, instant hotkey responsiveness, and immediate audio pipeline start.
- **True macOS App Bundle**: Packaged into a standard `Dictaphone.app` and downloadable `Dictaphone.dmg`.
- **System-level Permissions**: Accessibility and Microphone permissions attach directly to `Dictaphone.app` rather than terminal wrappers or Python binaries, preventing permission invalidation across updates.
- **Native Login Item**: Toggle "Launch at Login" in the menu bar to register with macOS 13+ `SMAppService` (visible in *System Settings → General → Login Items*).
- **Live Diagnostics**: All operational events, hotkey state transitions, recording metrics, and API responses are logged to `~/.dictaphone/dictaphone.log`.

---

## How It Works

```
[ Hold Right ⌘ ] ──> Starts AVAudioRecorder (16kHz Mono Linear PCM WAV)
                 ──> Displays floating HUD overlay (pulsing red dot + MM:SS timer)
                 ──> Changes menu bar icon from ◉ to ●

[ Speak ]        ──> Accidental press protection: typing another key (e.g. Cmd+Space)
                     cancels recording on release without transcribing.

[ Release ⌘ ]    ──> Hides HUD overlay, restores menu bar icon to ◉
                 ──> Stops recorder, discards if < 0.25s or < 2 KB
                 ──> Sends multipart/form-data to OpenAI API asynchronously
                 ──> Restores clipboard after pasting text via synthetic Cmd+V
```

---

## Repository Structure

```
mac-voice-ptt/
├── Package.swift                  # SwiftPM package manifest (macOS 13.0+)
├── Makefile                       # High-level build, packaging, and install targets
├── Resources/
│   └── Info.plist                 # Bundle metadata, LSUIElement, permission strings
├── Sources/
│   └── Dictaphone/
│       ├── main.swift             # Process entry point, single-instance lock (fcntl.flock)
│       ├── AppDelegate.swift      # NSApplication lifecycle coordinator & background policy
│       ├── Config.swift           # JSON config manager (~/.dictaphone/config.json & .env)
│       ├── HotkeyManager.swift    # Global keyboard listener & permission watcher
│       ├── AudioRecorder.swift    # 16kHz WAV capture via AVFoundation (with prepare & padding)
│       ├── Transcriber.swift      # Async URLSession multipart client for OpenAI API
│       ├── OverlayPanel.swift     # Floating HUD overlay with live timer & pulsing dot
│       ├── HistoryManager.swift   # History manager with JSON persistence, updates & combined copy
│       ├── HistoryWindowController.swift # Interactive history studio window (inline edit, multi-select)
│       ├── PreferencesWindowController.swift # Dedicated native preferences window (Cmd+,)
│       ├── Paster.swift           # Synthetic Cmd+V paste with clipboard restoration
│       ├── MenuBarController.swift# NSStatusItem menu bar UI (◉/●) and preferences
│       ├── LaunchAtLoginManager.swift # Native login item registration via SMAppService
│       └── Logger.swift           # Thread-safe persistent file logger with auto-rotation (2MB cap)
└── scripts/
    ├── build_app.sh               # Builds release binary, creates Dictaphone.app & signs
    ├── create_dmg.sh              # Packages Dictaphone.app into Dictaphone.dmg
    ├── install.sh                 # Copies to /Applications and launches
    └── uninstall.sh               # Removes Dictaphone from /Applications
```

---

## Component Details

### 1. Hotkey & Global Event Interception (`HotkeyManager.swift`)
- Listens for modifier keys globally across macOS using `NSEvent.addGlobalMonitorForEvents` and `NSEvent.addLocalMonitorForEvents`.
- Supported hotkeys:
  - **Right Command** (`cmd_r`, virtual key code `54`)
  - **Right Option / Alt** (`alt_r`, virtual key code `61`)
  - **Right Control** (`ctrl_r`, virtual key code `62`)
- **Accidental Press Protection**: If another non-modifier key is pressed while the hotkey is held (e.g. user pressed Cmd+Tab or Cmd+Space), recording is cancelled when the hotkey is released.
- **Dynamic Permission Watcher**: If Accessibility permission has not been granted at launch time, a background timer monitors `AXIsProcessTrusted()` every 1.5 seconds and automatically enables the event monitors the moment the user enables the toggle in System Settings, without requiring an app restart.

### 2. Audio Capture (`AudioRecorder.swift`)
- Configures `AVAudioRecorder` to produce standard Linear PCM 16-bit 16kHz Mono WAV files.
- Writes to a unique temporary file (`FileManager.default.temporaryDirectory`).
- Automatically cleans up recording files after transcription completes or on cancellation.
- Filters out micro-recordings (< 0.25 seconds or < 2 KB) to prevent accidental API calls.

### 3. Transcription Client (`Transcriber.swift`)
- Calls `https://api.openai.com/v1/audio/transcriptions` via `URLSession.shared.upload(for:from:)`.
- Default Model: `gpt-4o-mini-transcribe`.
- Multipart boundary builder sends `model`, `prompt`, `language` (if not `auto`), and raw audio bytes.
- Prompt:
  > *"The speaker alternates between Russian, German, and English. If it sounds Russian, it is Russian. Never transcribe Russian as Ukrainian, Polish, or any other Slavic language. If it sounds German, it is German. Never transcribe German as Dutch, Afrikaans, or any other Germanic language."*
- Decodes JSON response `{ "text": "..." }` and returns trimmed text.

### 4. Text Pasting (`Paster.swift`)
- Saves the current contents of `NSPasteboard.general`.
- Replaces pasteboard content with the transcribed text.
- Generates a synthetic `Cmd+V` keystroke using `CGEvent(keyboardEventSource:virtualKey:keyDown:)` posted to `kCGHIDEventTap`.
- Automatically restores the previous clipboard content after a 250ms delay.

### 5. Floating HUD Overlay (`OverlayPanel.swift`)
- Subclass of `NSPanel` with style masks `[.borderless, .nonactivatingPanel]`.
- Level set to `kCGAssistiveTechHighWindowLevel` (1500), collection behavior includes `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`. This guarantees the HUD floats above all applications, full-screen spaces, and modal Electron dialogs without stealing key focus.
- Cursor tracking via `NSEvent.mouseLocation` automatically positions the overlay in the top-right corner of the active display where the user is working.
- Renders an enforced dark high-contrast graphite pill (`#1a1a1f`, 95% opacity), pure white monospaced digits (18pt bold), and a glowing red recording indicator with a soft halo.
- Powered by a GCD `DispatchSourceTimer` scheduled on the main thread for rock-solid, jitter-free timer increments (`00:01`, `00:02`...).

### 6. Transcriptions History Studio (`HistoryManager.swift` & `HistoryWindowController.swift`)
- Automatically saves up to 25 recent transcriptions (configurable from 5 to 200 via Preferences) to `~/.dictaphone/history.json`.
- **Menu Bar Quick Access**: The 10 most recent entries are available directly in the **Recent Transcriptions ▸** submenu for one-click instant copying.
- **Dedicated History Window (`Cmd+H`)**:
  - **Dynamic Row Expansion**: Unselected rows remain compact single-line entries (38pt) with row numbers, text, and delete buttons aligned on the exact same baseline. Selecting a row smoothly expands it to display the full multi-line text with word wrapping.
  - **Inline Text Editing**: Double-click or edit any transcription text directly in the table cell with high contrast in both light and dark modes. Changes auto-save on edit finish, turning past dictations into reusable prompt templates.
  - **Single & Batch Deletion with Confirmation**: Remove unwanted entries with the row delete button (`✕`) or the `Backspace` / `Delete` key; destructive deletions require confirmation via native macOS sheet alerts.
  - **Multi-Selection & Combined Prompt Copying**: Select multiple items using `Cmd+Click`, `Shift+Click`, or mouse drag. The copy button transforms into **«Copy Combined (N)»** (or press `Cmd+C`), reversing the display order to natural chronological order (oldest to newest) and joining selected fragments with newlines (`\n`) into a structured, cohesive prompt ready to paste into LLMs.
  - **Visual & Haptic Copy Feedback**: Clicking copy triggers a green checkmark animation (`✓ Copied!`) on the button alongside trackpad haptic pulse feedback.
  - **Instant Search**: Filter through long histories with real-time text matching.

### 7. Dedicated Preferences Window (`PreferencesWindowController.swift`)
- Accessible via the menu bar item **Preferences...** or standard shortcut **`Cmd+,`**.
- **Push-to-Talk Hotkey**: Switch between Right Command ⌘, Right Option ⌥, and Right Control ⌃.
- **Speech Language**: Toggle between Auto-detection, Russian, German, and English.
- **OpenAI API Key**: Secure input field with Show/Hide toggle; synchronizes automatically with `config.json` and `~/.dictaphone/.env`.
- **Max Saved History**: Adjustable stepper from 5 to 200 items.
- **On History Window Open Focus**:
  - `First Item (Active & Expanded)`: Focuses the table view immediately, highlighting the latest entry in vibrant system blue with expanded text.
  - `Search Field (Ready for typing)`: Focuses the search bar immediately with no rows pre-selected, ready for quick filtering.
- **System Integration**: One-click toggles for "Launch at Login" (`SMAppService`) and active daemon state.

### 8. Diagnostics & Logging (`Logger.swift`)
- Thread-safe persistent file logger writing to `~/.dictaphone/dictaphone.log`.
- Direct access via the **Open Log File** menu bar item.
- Automatic 2 MB log rotation (`dictaphone.log` -> `dictaphone.log.1`).
- Clean session boundaries with empty line dividers and quoted transcription output.

### 9. Single-Instance Protection (`main.swift`)
- Uses kernel file locking via `fcntl.flock(fd, LOCK_EX | LOCK_NB)` on `~/.dictaphone/dictaphone.pid`.
- Immune to reboot PID reuse: when a process exits or system shuts down, the kernel automatically releases all file locks. Old PID files will never block startup.

---

## Build & Installation

### Requirements
- macOS 13.0 (Ventura) or newer (Sonoma, Sequoia, etc.).
- Apple Silicon (arm64) or Intel (x86_64).
- Swift 5.9+ (included in Xcode Command Line Tools: `xcode-select --install`).
- An OpenAI API Key (starts with `sk-`).

### 1. Build the Application
```bash
make app
```
Compiles the Swift code in release mode and bundles it into `build/Dictaphone.app`.

### 2. Create the Disk Image (DMG)
```bash
make dmg
```
Creates `build/Dictaphone.dmg` containing `Dictaphone.app` and a drag-and-drop shortcut to `/Applications`.

### 3. Install to `/Applications`
```bash
make install
```
Stops any existing Dictaphone process, copies `Dictaphone.app` to `/Applications`, strips quarantine attributes, and launches the app.

---

## macOS Permissions Setup (One-time)

To allow Dictaphone to record your voice and listen to global push-to-talk hotkeys, grant these permissions:

1. **Accessibility (Input Monitoring)**:
   - Open **System Settings → Privacy & Security → Accessibility**.
   - Enable the toggle for **Dictaphone**.
   - *(If re-installing an updated build, toggle the switch off and on again)*.

2. **Microphone**:
   - Open **System Settings → Privacy & Security → Microphone**.
   - Ensure the toggle for **Dictaphone** is enabled.

---

## Configuration & Logs

- **Configuration File**: `~/.dictaphone/config.json`
  ```json
  {
    "hotkey": "cmd_r",
    "language": "auto",
    "active": true
  }
  ```
- **API Key**:
  Can be configured directly in the app via the menu bar item: **◉ → OpenAI API Key...**.
  It is also read from `~/.dictaphone/.env` (`OPENAI_API_KEY=sk-...`) or the system environment.
- **Log File**: `~/.dictaphone/dictaphone.log`
  View real-time events and debug info:
  ```bash
  tail -f ~/.dictaphone/dictaphone.log
  ```

---

## Uninstallation

```bash
make uninstall
```
or simply drag `/Applications/Dictaphone.app` to the Trash. To remove stored configuration, delete `~/.dictaphone/`.
