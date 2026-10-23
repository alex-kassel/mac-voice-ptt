import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled {
                        return true
                    }
                    try SMAppService.mainApp.register()
                    NSLog("[LaunchAtLogin] Registered main app service.")
                    return true
                } else {
                    try SMAppService.mainApp.unregister()
                    NSLog("[LaunchAtLogin] Unregistered main app service.")
                    return true
                }
            } catch {
                NSLog("[LaunchAtLogin] Failed to toggle login item: %@", error.localizedDescription)
                return false
            }
        }
        return false
    }
}
