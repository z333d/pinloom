import Foundation

/// One-time cleanup for versions that redirected macOS screenshots. No
/// screenshot setting is changed unless a saved setting still belongs to us.
enum LegacyScreenshotSettings {
    static func restoreIfNeeded(
        defaults: UserDefaults = .standard,
        read: (String) -> Any? = readSystemValue,
        write: (String, Any?) -> Void = writeSystemValue
    ) {
        guard let saved = defaults.dictionary(forKey: "inboxSavedSettings") else {
            defaults.removeObject(forKey: "inboxEnabled")
            return
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tendedero/Screenshots", isDirectory: true).standardizedFileURL
        var restoredLocation = false
        for (key, savedKey) in [("location", "location"), ("location-screenshot", "locationScreenshot")] {
            guard let current = read(key) as? String,
                  URL(fileURLWithPath: (current as NSString).expandingTildeInPath).standardizedFileURL == folder else { continue }
            write(key, saved[savedKey])
            restoredLocation = true
        }
        if restoredLocation, (read("show-thumbnail") as? Bool) == false {
            write("show-thumbnail", saved["thumbnail"])
        }
        defaults.removeObject(forKey: "inboxSavedSettings")
        defaults.removeObject(forKey: "inboxEnabled")
    }

    private static let domain = "com.apple.screencapture" as CFString
    private static func readSystemValue(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }
    private static func writeSystemValue(_ key: String, _ value: Any?) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
