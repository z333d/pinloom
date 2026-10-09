import Foundation

/// Copies local data from the earlier build into Pinloom's own storage.
/// Original files and preferences remain available to the upstream app.
enum LegacyDataMigration {
    static let completedKey = "migratedFromTendedero"

    static func run(
        defaults: UserDefaults = .standard,
        legacy: UserDefaults? = UserDefaults(suiteName: "app.tendedero.Tendedero"),
        support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) throws {
        guard !defaults.bool(forKey: completedKey) else { return }
        let contentKeys = ["pegged", "stickyNotes", "referenceImages", "lastRemovedNote"]
        guard !contentKeys.contains(where: { defaults.object(forKey: $0) != nil }), let legacy else {
            defaults.set(true, forKey: completedKey)
            return
        }
        let sourceRoot = support.appendingPathComponent("Tendedero", isDirectory: true).standardizedFileURL
        let destinationRoot = support.appendingPathComponent("Pinloom", isDirectory: true).standardizedFileURL
        let fm = FileManager.default
        var mappedPaths: [String: String] = [:]

        func copy(_ source: URL, to destination: URL) throws {
            guard fm.fileExists(atPath: source.path) else { return }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: source, to: destination) }
        }
        func remapImage(_ path: String) throws -> String {
            if let mapped = mappedPaths[path] { return mapped }
            let source = URL(fileURLWithPath: path).standardizedFileURL
            let imports = sourceRoot.appendingPathComponent("Imports", isDirectory: true)
            let captures = sourceRoot.appendingPathComponent("Screenshots", isDirectory: true)
            let parent = source.deletingLastPathComponent()
            guard parent == imports || parent == captures,
                  fm.fileExists(atPath: source.path) else { return path }
            let destination = destinationRoot.appendingPathComponent(parent == imports ? "Imports" : "LegacyImages", isDirectory: true)
                .appendingPathComponent(source.lastPathComponent)
            try copy(source, to: destination)
            mappedPaths[path] = destination.path
            mappedPaths[source.resolvingSymlinksInPath().path] = destination.resolvingSymlinksInPath().path
            return destination.path
        }

        let paths = try (legacy.stringArray(forKey: "pegged") ?? []).map(remapImage)
        var records: [ReferenceRecord] = []
        if let data = legacy.data(forKey: "referenceImages") {
            records = try JSONDecoder().decode([ReferenceRecord].self, from: data).compactMap { record in
                guard record.filename == "\(record.id.uuidString).\((record.filename as NSString).pathExtension)" else { return nil }
                let source = sourceRoot.appendingPathComponent("References").appendingPathComponent(record.filename)
                guard fm.fileExists(atPath: source.path) else { return nil }
                try copy(source, to: destinationRoot.appendingPathComponent("References").appendingPathComponent(record.filename))
                return ReferenceRecord(id: record.id, sourcePath: try remapImage(record.sourcePath),
                                       filename: record.filename, frame: record.frame, zoom: record.zoom)
            }
        }
        let referenceData = try JSONEncoder().encode(records)
        // Commit preferences only after file copies succeed. A failed copy
        // leaves migration retryable and never removes the source data.
        for key in ["stickyNotes", "lastRemovedNote", "soundOff"] {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        for key in ["peggedScales", "peggedPositions"] {
            if let values = legacy.dictionary(forKey: key) {
                var remapped: [String: Any] = [:]
                for original in values.keys.sorted() { remapped[mappedPaths[original] ?? original] = values[original] }
                defaults.set(remapped, forKey: key)
            }
        }
        if legacy.object(forKey: "pegged") != nil { defaults.set(paths, forKey: "pegged") }
        if legacy.object(forKey: "referenceImages") != nil {
            defaults.set(referenceData, forKey: "referenceImages")
        }
        defaults.set(true, forKey: completedKey)
    }
}
