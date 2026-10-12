import AppKit
import CoreServices
import UniformTypeIdentifiers

enum ScreenshotSource: String, CaseIterable {
    case clipboard, folder
    var title: String { self == .clipboard ? L("Clipboard image") : L("Latest image in screenshot folder") }
}

@MainActor
final class RecentScreenshot {
    let defaults: UserDefaults
    private var previousClipboard: (name: String, count: Int, url: URL)?
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var source: ScreenshotSource {
        get { ScreenshotSource(rawValue: defaults.string(forKey: "recentScreenshotSource") ?? "") ?? .clipboard }
        set { defaults.set(newValue.rawValue, forKey: "recentScreenshotSource") }
    }
    var customFolder: URL? {
        get { defaults.string(forKey: "recentScreenshotFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue?.path, forKey: "recentScreenshotFolder") }
    }
    var folder: URL {
        customFolder ?? Self.systemFolder()
    }
    static func systemFolder(read: (String) -> String? = {
        CFPreferencesCopyAppValue($0 as CFString, "com.apple.screencapture" as CFString) as? String
    }) -> URL {
        for key in ["location-screenshot", "location"] {
            if let path = read(key), !path.isEmpty {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Called only on an explicit action; never observes clipboard content.
    func clipboardImage(from pasteboard: NSPasteboard = .general, destination: URL = ImageImport.folder) throws -> URL? {
        let count = pasteboard.changeCount
        let files = ImageImport.urls(from: pasteboard)
        if !files.isEmpty {
            return files.first { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        }
        if let previous = previousClipboard, previous.name == pasteboard.name.rawValue,
           previous.count == count, FileManager.default.fileExists(atPath: previous.url.path) { return previous.url }
        guard let url = try ImageImport.imageFile(from: pasteboard, in: destination) else { return nil }
        guard pasteboard.changeCount == count else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        previousClipboard = (pasteboard.name.rawValue, count, url)
        return url
    }

    func newestFile() async throws -> URL? {
        let folder = self.folder
        let anyImage = customFolder != nil
        return try await Task.detached(priority: .userInitiated) {
            try Self.newestImage(in: folder, acceptsAnyImage: anyImage)
        }.value
    }
    nonisolated static func newestImage(in folder: URL, acceptsAnyImage: Bool,
                                       isScreenshot: (URL) -> Bool = isScreenshotFile) throws -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        return files.compactMap { url -> (URL, Date)? in
            guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  values.isSymbolicLink != true, acceptsAnyImage || isScreenshot(url) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.max { left, right in
            left.1 == right.1 ? left.0.path < right.0.path : left.1 < right.1
        }?.0
    }
    nonisolated private static func isScreenshotFile(_ url: URL) -> Bool {
        if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           (MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool) == true { return true }
        // Metadata may arrive after the file. Native capture names cover that gap.
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["screenshot ", "screen shot ", "截屏", "屏幕快照", "captura de pantalla ", "bildschirmfoto "]
            .contains { name.hasPrefix($0) }
    }
}
