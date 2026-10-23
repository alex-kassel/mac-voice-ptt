# Dictaphone — Push-to-Talk Voice Transcription for macOS

**Dictaphone** is a native, lightweight macOS push-to-talk voice transcription utility. Hold down a configurable modifier key (by default, Right Command ⌘), speak into your microphone, and release: your speech is transcribed via OpenAI's `gpt-4o-mini-transcribe` and instantly typed/pasted at your current cursor position.

Built completely in **Swift** with **zero external dependencies**, relying exclusively on native macOS frameworks (`AppKit`, `AVFoundation`, `CoreGraphics`, `ServiceManagement`, `Foundation`).

---

## Highlights

- **Ultra-lightweight**: App bundle is **~280 KB** (compared to ~150+ MB for Python + virtualenv).
- **Minimal memory footprint**: Runs quietly in the menu bar consuming **~15–25 MB RAM** (vs 120+ MB for Python).
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
- Level set to `.floating`, collection behavior includes `.canJoinAllSpaces` and `.stationary`.
- Positioned in the top-right corner of the active display, just below the menu bar.
- Renders a translucent dark background (alpha 0.90), a pulsing red recording indicator with soft glow, and a monospaced elapsed timer (`00:00`).

### 6. Single-Instance Protection (`main.swift`)
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
