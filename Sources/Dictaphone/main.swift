import Foundation
import AppKit

// MARK: - Single Instance Lock via fcntl.flock

let pidPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".dictaphone")
    .appendingPathComponent("dictaphone.pid")

try? FileManager.default.createDirectory(at: pidPath.deletingLastPathComponent(), withIntermediateDirectories: true)

let fd = open(pidPath.path, O_CREAT | O_RDWR, 0o644)
if fd >= 0 {
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        NSLog("Dictaphone is already running.")
        exit(0)
    }
    // Write current PID into the file
    let pidStr = "\(getpid())\n"
    ftruncate(fd, 0)
    pwrite(fd, pidStr, pidStr.utf8.count, 0)
}

// MARK: - App Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
