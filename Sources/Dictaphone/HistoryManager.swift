import Foundation
import AppKit
import UserNotifications

final class HistoryManager {
    static let shared = HistoryManager()

    private let fileURL: URL
    private let lock = NSLock()
    private var history: [String] = []

    private var maxHistoryCount: Int {
        return max(5, ConfigManager.shared.config.maxHistoryItems)
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".dictaphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")

        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        self.history = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: fileURL)
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        // Avoid exact duplicate as top item
        if history.first == trimmed {
            return
        }

        history.insert(trimmed, at: 0)
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }

        save()
        Logger.log("[HistoryManager] Added transcription to history (count: %ld)", history.count)
    }

    func getHistory() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return history
    }

    func update(index: Int, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        guard index >= 0 && index < history.count else { return }
        history[index] = trimmed
        save()
        Logger.log("[HistoryManager] Updated item #%ld (%ld chars)", index + 1, trimmed.count)
    }

    func delete(index: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard index >= 0 && index < history.count else { return }
        history.remove(at: index)
        save()
        Logger.log("[HistoryManager] Deleted item #%ld (remaining: %ld)", index + 1, history.count)
    }

    func delete(indexes: [Int]) {
        lock.lock()
        defer { lock.unlock() }

        let sorted = indexes.sorted(by: >)
        for idx in sorted {
            if idx >= 0 && idx < history.count {
                history.remove(at: idx)
            }
        }
        save()
        Logger.log("[HistoryManager] Deleted %ld items (remaining: %ld)", indexes.count, history.count)
    }

    func copyToClipboard(index: Int) -> Bool {
        lock.lock()
        guard index >= 0 && index < history.count else {
            lock.unlock()
            return false
        }
        let text = history[index]
        lock.unlock()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Logger.log("[HistoryManager] Copied item #%ld to clipboard (%ld chars)", index + 1, text.count)
        sendNotification(title: "Dictaphone: Copied to Clipboard", text: text)
        return true
    }

    func copyCombined(indexes: [Int], separator: String = " ") -> String? {
        lock.lock()
        defer { lock.unlock() }

        // Sort descending so the earlier spoken items appear first in combined prompt
        // Note: history[0] is newest, history[N] is older.
        // If user selects multiple items, we order them chronologically (oldest to newest):
        let sorted = indexes.sorted(by: >)
        var texts: [String] = []
        for idx in sorted {
            if idx >= 0 && idx < history.count {
                texts.append(history[idx])
            }
        }

        guard !texts.isEmpty else { return nil }
        let combined = texts.joined(separator: separator)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(combined, forType: .string)

        Logger.log("[HistoryManager] Copied %ld combined items to clipboard (%ld chars)", texts.count, combined.count)
        sendNotification(title: "Dictaphone: \(texts.count) Items Copied (Combined)", text: combined)
        return combined
    }

    func clear() {
        lock.lock()
        history.removeAll()
        save()
        lock.unlock()
        Logger.log("[HistoryManager] History cleared by user.")
    }

    private func sendNotification(title: String, text: String) {
        let preview = text.count > 60 ? String(text.prefix(60)) + "..." : text
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = preview
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
