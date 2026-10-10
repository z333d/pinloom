import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct MediaCard: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case video, webpage }
    var id = UUID()
    let kind: Kind
    var source: URL
    let filename: String?
    let title: String
    var width: Double
    var height: Double
    var x: Double?
    var y: Double?
    var playbackTime: Double = 0

    func size(available: CGSize) -> CGSize {
        CardSizing.noteSize(CGSize(width: max(kind == .webpage ? 320 : 280, width),
                                   height: max(kind == .webpage ? 280 : 220, height)), available: available)
    }
}

enum MediaImport {
    static func webpageURL(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: text) else { return nil }
        if parts.scheme == nil {
            guard text.contains("."), let qualified = URLComponents(string: "https://" + text) else { return nil }
            parts = qualified
        }
        guard ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        return parts.url
    }

    static func webpageURL(from pasteboard: NSPasteboard) -> URL? {
        if let text = pasteboard.string(forType: .URL), let url = webpageURL(text) { return url }
        return pasteboard.string(forType: .string).flatMap(webpageURL)
    }

    static func isVideo(_ url: URL) -> Bool {
        url.isFileURL && UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    static func validateVideo(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
