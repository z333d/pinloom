import AppKit
import AVFoundation
import CoreVideo
import SwiftUI
import WebKit
import XCTest
@testable import Pinloom

final class MediaTests: XCTestCase {
    private let suite = "PinloomTests.Media.\(UUID().uuidString)"
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    override func setUpWithError() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    func testURLParsingAndClipboardAcceptWebLinksWithoutTakingPlainNotesOrScripts() {
        XCTAssertEqual(MediaImport.webpageURL(" example.com/reference ")?.absoluteString, "https://example.com/reference")
        for text in ["finish the report", "javascript:alert(1)", "file:///etc/passwd", "https://user:password@example.com", "https://"] {
            XCTAssertNil(MediaImport.webpageURL(text))
        }
        let clipboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { clipboard.releaseGlobally() }
        clipboard.setString("https://example.com/page", forType: .string)
        XCTAssertTrue(ImageImport.supports(clipboard))
        XCTAssertEqual(MediaImport.webpageURL(from: clipboard)?.host, "example.com")
        XCTAssertEqual(clipboard.string(forType: .string), "https://example.com/page")
    }

    @MainActor
    func testWebpageCardsRestoreURLLayoutAndDoNotChangeOtherCards() throws {
        let folder = directory.appendingPathComponent("Media")
        let line = Line(defaults: defaults, mediaFolder: folder)
        let url = try XCTUnwrap(MediaImport.webpageURL("https://example.com/reference"))
        let id = try XCTUnwrap(line.addWebpage(url))
        XCTAssertEqual(line.addWebpage(url), id)
        let note = line.addNote()
        line.setNoteText(note, text: "Keep the note")
        line.moveMedia(id, to: CGPoint(x: 400, y: 180))
        line.resizeMedia(id, to: CGSize(width: 650, height: 600))
        line.updateMedia(id, url: URL(string: "https://example.com/next"))
        let restored = Line(defaults: defaults, mediaFolder: folder)
        XCTAssertEqual(restored.media, line.media)
        XCTAssertEqual(restored.media.first?.source.path, "/next")
        XCTAssertEqual(restored.notes.first?.text, "Keep the note")
        XCTAssertEqual(restored.totalCount, 2)
        restored.resetPositions()
        XCTAssertNil(restored.media.first?.x)
        XCTAssertFalse(line.revealed)
        restored.removeMedia(id)
        XCTAssertTrue(Line(defaults: defaults, mediaFolder: folder).media.isEmpty)
        XCTAssertEqual(restored.notes.count, 1)
    }

    @MainActor
    func testVideosOwnCopiesSurviveSourceDeletionAndStartPausedMuted() async throws {
        let source = try await video()
        let original = try Data(contentsOf: source)
        let folder = directory.appendingPathComponent("Media")
        let line = Line(defaults: defaults, mediaFolder: folder)
        let id = try await line.addVideo(source)
        let duplicate = try await line.addVideo(source)
        XCTAssertEqual(duplicate, id)
        let card = try XCTUnwrap(line.media.first)
        XCTAssertEqual(try Data(contentsOf: line.mediaURL(card)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        try FileManager.default.removeItem(at: source)
        let restored = Line(defaults: defaults, mediaFolder: folder)
        XCTAssertEqual(restored.media.first?.id, id)
        restored.setShown(true)
        let host = NSHostingView(rootView: MediaCardView(card: try XCTUnwrap(restored.media.first), line: restored, anchor: .zero))
        host.frame = NSRect(x: 0, y: 0, width: 404, height: 274)
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let body = try XCTUnwrap(descendants(host).first { $0 is MediaCardBody } as? MediaCardBody)
        defer { body.dispose() }
        let player = try XCTUnwrap(body.playerView?.player)
        XCTAssertTrue(player.isMuted)
        XCTAssertEqual(player.rate, 0)
        let deadline = Date().addingTimeInterval(10)
        while player.currentItem?.status == .unknown && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(player.currentItem?.status, .readyToPlay)
        player.play()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThan(player.rate, 0)
        restored.setShown(false)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(player.rate, 0)
        XCTAssertGreaterThanOrEqual(restored.media.first?.playbackTime ?? -1, 0)
        restored.removeMedia(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.mediaURL(card).path))
    }

    @MainActor
    func testCorruptVideoAndUnownedStoredFilesCannotBecomeCardsOrDeleteOriginals() async throws {
        let corrupt = directory.appendingPathComponent("corrupt.mov")
        try Data("not a video".utf8).write(to: corrupt)
        let folder = directory.appendingPathComponent("Media")
        let line = Line(defaults: defaults, mediaFolder: folder)
        do { _ = try await line.addVideo(corrupt); XCTFail("Corrupt videos must be rejected") } catch {}
        XCTAssertTrue(line.media.isEmpty)
        let unsafe = MediaCard(kind: .video, source: corrupt, filename: "../corrupt.mov", title: "invalid", width: 384, height: 260)
        defaults.set(try JSONEncoder().encode([unsafe]), forKey: "mediaCards")
        let restored = Line(defaults: defaults, mediaFolder: folder)
        XCTAssertTrue(restored.media.isEmpty)
        restored.removeMedia(unsafe.id)
        XCTAssertEqual(try String(contentsOf: corrupt), "not a video")
    }

    @MainActor
    func testHiddenWebpageDoesNotLoadAndNativeContentAndResizeRemainHitTestable() async throws {
        _ = NSApplication.shared
        let line = Line(defaults: defaults, mediaFolder: directory.appendingPathComponent("Media"))
        let id = try XCTUnwrap(line.addWebpage(URL(string: "https://example.invalid")!))
        let card = try XCTUnwrap(line.media.first)
        let host = NSHostingView(rootView: MediaCardView(card: card, line: line, anchor: .zero))
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 520, height: 420), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let body = try XCTUnwrap(descendants(host).first { $0 is MediaCardBody } as? MediaCardBody)
        defer { body.dispose() }
        XCTAssertNil(body.webView?.url)
        XCTAssertFalse(body.webView?.isLoading ?? true)
        XCTAssertNil(body.loadedURL)
        XCTAssertEqual(body.webView?.configuration.mediaTypesRequiringUserActionForPlayback, .all)
        let grip = try XCTUnwrap(descendants(host).first { $0 is NoteResizeView })
        let point = grip.convert(NSPoint(x: grip.bounds.midX, y: grip.bounds.midY), to: nil)
        XCTAssertTrue(panel.interactiveView(atWindowPoint: point) === grip)
        let native = try XCTUnwrap(body.webView)
        XCTAssertTrue(panel.interactiveView(atWindowPoint: native.convert(NSPoint(x: 20, y: 20), to: nil)) === body)
        // Restoration creates the native content while the board is hidden.
        // Showing it must update the representable even when its card is unchanged.
        line.setShown(true)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(body.loadedURL, card.source)
        XCTAssertTrue(body.webView === native)
        line.resizeMedia(id, to: CGSize(width: 9000, height: 9000))
        XCTAssertLessThanOrEqual(line.media.first?.width ?? .infinity, 1184)
        XCTAssertLessThanOrEqual(line.media.first?.height ?? .infinity, 800)
    }

    @MainActor
    func testNativeWebViewRendersInteractiveHTMLAndKeepsItsNavigationStateDuringResize() async throws {
        _ = NSApplication.shared
        let line = Line(defaults: defaults, mediaFolder: directory.appendingPathComponent("Media"))
        let id = try XCTUnwrap(line.addWebpage(URL(string: "https://pinloom.example.test")!))
        let body = MediaCardBody(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        defer { body.dispose() }
        body.configure(card: try XCTUnwrap(line.media.first), line: line)
        let web = try XCTUnwrap(body.webView)
        // A local document exercises real WebKit without a network dependency.
        web.loadHTMLString("<title>Pinloom fixture</title><input id='memo' value='Editable'><a href='#detail'>Details</a><p id='detail'>Reference content</p>",
                           baseURL: URL(string: "https://pinloom.example.test"))
        let deadline = Date().addingTimeInterval(15)
        var rendered = false
        while Date() < deadline {
            if let title = try? await web.evaluateJavaScript("document.title") as? String, title == "Pinloom fixture" {
                rendered = true; break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(rendered, "The card must render an actual webpage")
        _ = try await web.evaluateJavaScript("document.querySelector('#memo').value = 'Changed'; document.querySelector('a').click()")
        line.resizeMedia(id, to: CGSize(width: 600, height: 450))
        body.configure(card: try XCTUnwrap(line.media.first), line: line)
        XCTAssertTrue(body.webView === web, "Resizing must retain the page and typed input")
        let contents = try await web.evaluateJavaScript("document.querySelector('#memo').value") as? String
        XCTAssertEqual(contents, "Changed")
    }

    @MainActor
    func testNewVideoScrollsIntoAnOverflowingBoardWithoutTakingKeyboardFocus() async throws {
        let line = Line(defaults: defaults, mediaFolder: directory.appendingPathComponent("Media"))
        line.viewportWidth = 800; line.availableHeight = 600
        for _ in 0..<4 { _ = line.addNote() }
        let id = try await line.addVideo(try await video())
        line.setShown(true)
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 500), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func bodies(_ view: NSView) -> [MediaCardBody] { (view as? MediaCardBody).map { [$0] } ?? view.subviews.flatMap(bodies) }
        let body = try XCTUnwrap(bodies(host).first)
        defer { body.dispose() }
        XCTAssertTrue(host.bounds.intersects(body.convert(body.bounds, to: host)), "New media must scroll into view")
        XCTAssertEqual(line.mediaFocusRequest, id)
        XCTAssertFalse(panel.isKeyWindow)
    }

    @MainActor
    private func video() async throws -> URL {
        let url = directory.appendingPathComponent("playback-check.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            guard input.isReadyForMoreMediaData else { throw CocoaError(.fileWriteUnknown) }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180,
                                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
            context.setFillColor(NSColor(srgbRed: 0.12, green: 0.26, blue: 0.24, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            context.setFillColor(NSColor(srgbRed: 0.94, green: 0.43, blue: 0.32, alpha: 1).cgColor)
            context.fill(CGRect(x: frame * 4, y: 55, width: 70, height: 70))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        if let path = ProcessInfo.processInfo.environment["PINLOOM_VIDEO_FIXTURE"] {
            let target = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: url, to: target)
        }
        return url
    }
}
