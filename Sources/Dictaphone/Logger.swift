import Foundation

final class Logger {
    static let shared = Logger()
    private let logFileURL: URL
    private let backupFileURL: URL
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.fcc.dictaphone.logger", qos: .utility)
    private let maxLogSizeBytes: UInt64 = 2 * 1024 * 1024 // 2 MB maximum file size

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".dictaphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.logFileURL = dir.appendingPathComponent("dictaphone.log")
        self.backupFileURL = dir.appendingPathComponent("dictaphone.log.1")

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        openHandle()
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        self.fileHandle?.seekToEndOfFile()
    }

    static func log(_ message: String, _ args: CVarArg...) {
        let formatted = String(format: message, arguments: args)
        shared.write(formatted)
    }

    static func writeRaw(_ rawText: String) {
        shared.queue.async {
            shared.rotateIfNeeded()
            guard let handle = shared.fileHandle, let data = rawText.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    /// Outputs an empty line preceding every new dictation session and prints a distinct start banner
    static func startSession(hotkey: String) {
        writeRaw("\n")
        log("--------------------------------------------------------------------------------")
        log(">>> [DICTATION SESSION START] Hotkey: %@", hotkey)
    }

    /// Prints a prominent success banner with the transcribed text and auto-paste status
    static func endSessionSuccess(text: String, charsCount: Int) {
        log("[Transcription] Result (%ld chars):", charsCount)
        log(">>> \"%@\"", text)
        log("[Paster] Synthetic Cmd+V dispatched to active application.")
        log("-------------------- [DICTATION SESSION FINISHED] --------------------\n")
    }

    /// Prints a clean notice when audio was silent or below threshold
    static func endSessionSilent() {
        log("[Transcription] Audio was silent or below voice threshold (empty text).")
        log("-------------------- [DICTATION SESSION DISCARDED] --------------------\n")
    }

    /// Prints a clean notice when recording was cancelled by user
    static func endSessionCancelled(reason: String) {
        log("[Dictation] Cancelled: %@", reason)
        log("-------------------- [DICTATION SESSION CANCELLED] --------------------\n")
    }

    /// Prints a prominent failure banner
    static func endSessionError(error: String) {
        writeRaw("\n")
        log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        log("!!! [DICTATION FAILED: ERROR OCCURRED] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        log("! Error: %@", error)
        log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n")
    }

    private func write(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("%@", message)

        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateIfNeeded()

            guard let handle = self.fileHandle, let data = line.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    private func rotateIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)
        let size = (attrs?[.size] as? UInt64) ?? 0

        if size >= maxLogSizeBytes {
            // Close current handle
            try? fileHandle?.close()
            fileHandle = nil

            // Rotate: dictaphone.log -> dictaphone.log.1
            try? FileManager.default.removeItem(at: backupFileURL)
            try? FileManager.default.moveItem(at: logFileURL, to: backupFileURL)

            // Re-open fresh log file
            openHandle()
            if let handle = fileHandle, let notice = "[\(dateFormatter.string(from: Date()))] [Logger] Log rotated (exceeded 2MB limit).\n".data(using: .utf8) {
                handle.write(notice)
            }
        }
    }
}
