import Foundation

enum HistoryFocusMode: String, Codable, CaseIterable {
    case firstItem = "first_item"
    case searchField = "search_field"

    var title: String {
        switch self {
        case .firstItem: return "First Item (Active & Expanded)"
        case .searchField: return "Search Field (Ready for typing)"
        }
    }
}

struct AppConfig: Codable {
    var hotkey: String = "cmd_r"
    var language: String = "auto"
    var active: Bool = true
    var apiKey: String? = nil
    var maxHistoryItems: Int = 25
    var historyFocusMode: String = "first_item"

    static let validHotkeys: Set<String> = ["cmd_r", "alt_r", "ctrl_r"]
    static let validLanguages: Set<String> = ["auto", "ru", "de", "en"]
    static let validFocusModes: Set<String> = ["first_item", "search_field"]

    var focusMode: HistoryFocusMode {
        get { HistoryFocusMode(rawValue: historyFocusMode) ?? .firstItem }
        set { historyFocusMode = newValue.rawValue }
    }
}

final class ConfigManager {
    static let shared = ConfigManager()

    private let fileManager = FileManager.default
    private let configDir: URL
    private let configFile: URL
    private let envFile: URL

    private(set) var config: AppConfig

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".dictaphone", isDirectory: true)
        configFile = configDir.appendingPathComponent("config.json")
        envFile = configDir.appendingPathComponent(".env")

        try? fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        config = ConfigManager.load(from: configFile)
    }

    private static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        var valid = loaded
        if !AppConfig.validHotkeys.contains(valid.hotkey) {
            valid.hotkey = "cmd_r"
        }
        if !AppConfig.validLanguages.contains(valid.language) {
            valid.language = "auto"
        }
        if !AppConfig.validFocusModes.contains(valid.historyFocusMode) {
            valid.historyFocusMode = "first_item"
        }
        return valid
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFile, options: .atomic)
        }
    }

    func update(hotkey: String) {
        guard AppConfig.validHotkeys.contains(hotkey) else { return }
        config.hotkey = hotkey
        save()
    }

    func update(language: String) {
        guard AppConfig.validLanguages.contains(language) else { return }
        config.language = language
        save()
    }

    func update(active: Bool) {
        config.active = active
        save()
    }

    func update(maxHistoryItems: Int) {
        config.maxHistoryItems = max(5, min(200, maxHistoryItems))
        save()
    }

    func update(historyFocusMode: String) {
        guard AppConfig.validFocusModes.contains(historyFocusMode) else { return }
        config.historyFocusMode = historyFocusMode
        save()
    }

    func update(apiKey: String) {
        let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.apiKey = clean.isEmpty ? nil : clean
        save()

        // Also save to ~/.dictaphone/.env for compatibility with other tools
        if !clean.isEmpty {
            let content = "OPENAI_API_KEY=\(clean)\n"
            try? content.write(to: envFile, atomically: true, encoding: .utf8)
        }
    }

    func getOpenAIKey() -> String? {
        // 1. In-memory config / config.json
        if let key = config.apiKey, !key.isEmpty {
            return key
        }

        // 2. ~/.dictaphone/.env
        if let envData = try? String(contentsOf: envFile, encoding: .utf8) {
            for line in envData.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("OPENAI_API_KEY=") {
                    let key = String(trimmed.dropFirst("OPENAI_API_KEY=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
                    if !key.isEmpty {
                        return key
                    }
                }
            }
        }

        // 3. Process environment
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        return nil
    }
}
