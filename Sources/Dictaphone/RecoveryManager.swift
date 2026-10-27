import Foundation

struct FailedAudioMetadata: Codable {
    let timestamp: Date
    let duration: TimeInterval
    let language: String
    let fileExtension: String
    let errorDescription: String
}

final class RecoveryManager {
    static let shared = RecoveryManager()

    private let fileManager = FileManager.default
    private let recoveryDir: URL
    private let metadataFile: URL

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        recoveryDir = home.appendingPathComponent(".dictaphone/recovery", isDirectory: true)
        metadataFile = recoveryDir.appendingPathComponent("last_failed.json")
        try? fileManager.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
    }

    var hasFailedAudio: Bool {
        return getFailedAudioURL() != nil
    }

    func getFailedAudioURL() -> URL? {
        guard let meta = loadMetadata() else { return nil }
        let audioURL = recoveryDir.appendingPathComponent("last_failed.\(meta.fileExtension)")
        if fileManager.fileExists(atPath: audioURL.path) {
            return audioURL
        }
        return nil
    }

    func getLastFailedAudioInfo() -> (url: URL, language: String, duration: TimeInterval, error: String)? {
        guard let meta = loadMetadata(), let url = getFailedAudioURL() else { return nil }
        return (url, meta.language, meta.duration, meta.errorDescription)
    }

    func saveFailedAudio(from sourceURL: URL, language: String, duration: TimeInterval, error: String) {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension.lowercased()
        let destAudioURL = recoveryDir.appendingPathComponent("last_failed.\(ext)")

        clearFailedAudio()

        do {
            if fileManager.fileExists(atPath: destAudioURL.path) {
                try fileManager.removeItem(at: destAudioURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destAudioURL)

            let meta = FailedAudioMetadata(
                timestamp: Date(),
                duration: duration,
                language: language,
                fileExtension: ext,
                errorDescription: error
            )
            let data = try JSONEncoder().encode(meta)
            try data.write(to: metadataFile, options: .atomic)

            Logger.log("[RecoveryManager] Successfully saved failed audio (duration: %.1fs, file: %@)", duration, destAudioURL.lastPathComponent)
        } catch {
            Logger.log("[RecoveryManager] Failed to save recovery audio: %@", error.localizedDescription)
        }
    }

    func clearFailedAudio() {
        let extensions = ["m4a", "wav"]
        for ext in extensions {
            let path = recoveryDir.appendingPathComponent("last_failed.\(ext)")
            try? fileManager.removeItem(at: path)
        }
        try? fileManager.removeItem(at: metadataFile)
        Logger.log("[RecoveryManager] Cleared recovery audio cache.")
    }

    private func loadMetadata() -> FailedAudioMetadata? {
        guard let data = try? Data(contentsOf: metadataFile),
              let meta = try? JSONDecoder().decode(FailedAudioMetadata.self, from: data) else {
            return nil
        }
        return meta
    }
}
