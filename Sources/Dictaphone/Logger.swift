import Foundation

final class Logger {
    static let shared = Logger()
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.fcc.dictaphone.logger", qos: .utility)

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".dictaphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.logFileURL = dir.appendingPathComponent("dictaphone.log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        self.fileHandle?.seekToEndOfFile()

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    static func log(_ message: String, _ args: CVarArg...) {
        let formatted = String(format: message, arguments: args)
        shared.write(formatted)
    }

    private func write(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("%@", message)

        queue.async { [weak self] in
            guard let handle = self?.fileHandle, let data = line.data(using: .utf8) else { return }
            handle.write(data)
        }
    }
}
