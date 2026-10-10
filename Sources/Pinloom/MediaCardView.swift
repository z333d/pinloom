import SwiftUI
import AVKit
import WebKit

struct MediaCardView: View {
    let card: MediaCard
    @ObservedObject var line: Line
    let anchor: CGPoint
    @StateObject private var motion = HangingMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = card.size(available: line.availableSize)
        VStack(spacing: -12) {
            Clothespin().frame(width: 32, height: 26)
                .overlay(MediaClipArea(card: card, line: line, anchor: anchor, motion: motion, reduceMotion: reduceMotion))
                .zIndex(1)
            MediaContent(card: card, line: line)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 22).allowsHitTesting(false)
                        .overlay(MediaResizeArea(card: card, line: line).frame(width: 26, height: 22))
                }
        }
        .frame(width: size.width + 20, height: size.height + 14)
        .rotationEffect(.degrees(motion.degrees), anchor: .top)
        .onDisappear { motion.stop() }
    }
}

private struct MediaClipArea: NSViewRepresentable {
    let card: MediaCard
    let line: Line
    let anchor: CGPoint
    let motion: HangingMotion
    let reduceMotion: Bool
    func makeNSView(context: Context) -> ClipMoveView { ClipMoveView() }
    func updateNSView(_ view: ClipMoveView, context: Context) {
        view.anchor = anchor
        view.onMove = { point in
            line.moveMedia(card.id, to: point)
            if !reduceMotion, let current = line.media.first(where: { $0.id == card.id }), let x = current.x, let y = current.y {
                motion.move(to: CGPoint(x: x, y: y))
            }
        }
        view.onMoveState = { moving in
            line.movingItemID = moving ? card.id : nil
            if moving {
                line.frontmostItemID = card.id
                if !reduceMotion { motion.begin(at: anchor, length: card.size(available: line.availableSize).height / 2) }
            } else { motion.release() }
        }
        view.resetTitle = L("Reset card position")
        view.onReset = { line.resetMediaPosition(card.id) }
    }
}

private struct MediaResizeArea: NSViewRepresentable {
    let card: MediaCard
    let line: Line
    func makeNSView(context: Context) -> NoteResizeView { NoteResizeView() }
    func updateNSView(_ view: NoteResizeView, context: Context) {
        view.size = card.size(available: line.availableSize)
        view.onResize = { line.resizeMedia(card.id, to: $0) }
        view.onState = { line.resizingID = $0 ? card.id : nil }
    }
}

private struct MediaContent: NSViewRepresentable {
    let card: MediaCard
    @ObservedObject var line: Line
    func makeNSView(context: Context) -> MediaCardBody { MediaCardBody() }
    func updateNSView(_ view: MediaCardBody, context: Context) { view.configure(card: card, line: line) }
    static func dismantleNSView(_ view: MediaCardBody, coordinator: ()) { view.dispose() }
}

/// Native playback and WebKit keep keyboard, selection, scrolling and media
/// controls inside each card. The resize grip lives outside their viewport.
final class MediaCardBody: NSView, WKNavigationDelegate, WKUIDelegate {
    override var isFlipped: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private let title = NSTextField(labelWithString: "")
    private let back = NSButton()
    private let forward = NSButton()
    private let reload = NSButton()
    private let external = NSButton()
    private let remove = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private(set) var playerView: AVPlayerView?
    private(set) var webView: WKWebView?
    private var observation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var cardID: UUID?
    private(set) var loadedURL: URL?
    private var shown = false
    private var onRemove: () -> Void = {}
    private var onURL: (URL) -> Void = { _ in }
    private var onTime: (Double) -> Void = { _ in }
    private var currentURL: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        title.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.alignment = .center
        status.isHidden = true
        progress.style = .spinning; progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        button(back, symbol: "chevron.left", label: L("Back"), action: #selector(goBack))
        button(forward, symbol: "chevron.right", label: L("Forward"), action: #selector(goForward))
        button(reload, symbol: "arrow.clockwise", label: L("Reload"), action: #selector(reloadContent))
        button(external, symbol: "arrow.up.right.square", label: L("Open in default app"), action: #selector(openExternal))
        button(remove, symbol: "xmark", label: L("Remove card"), action: #selector(removeCard))
        [title, back, forward, reload, external, remove, status, progress].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func button(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.bezelStyle = .inline; button.showsBorderOnlyWhileMouseInside = true
        button.toolTip = label; button.target = self; button.action = action
    }

    func configure(card: MediaCard, line: Line) {
        let newCard = cardID != card.id
        if newCard { dispose() }
        onRemove = { line.removeMedia(card.id) }
        onURL = { line.updateMedia(card.id, url: $0) }
        onTime = { line.updateMedia(card.id, playbackTime: $0) }
        let url = line.mediaURL(card)
        if newCard {
            cardID = card.id; currentURL = url
            title.stringValue = card.title; title.toolTip = url.absoluteString
            if card.kind == .video {
                let view = AVPlayerView()
                view.controlsStyle = .inline
                view.videoGravity = .resizeAspect
                view.showsFullScreenToggleButton = false
                let player = AVPlayer(url: url)
                player.isMuted = true
                view.player = player
                playerView = view; addSubview(view, positioned: .below, relativeTo: title)
                if card.playbackTime > 0 { player.seek(to: CMTime(seconds: card.playbackTime, preferredTimescale: 600)) }
                observation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard item.status == .failed else { return }
                        self?.showFailure(L("Could not play video"))
                    }
                }
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 2, preferredTimescale: 600), queue: .main) { [weak self] time in
                    MainActor.assumeIsolated { self?.onTime(time.seconds) }
                }
            } else {
                let configuration = WKWebViewConfiguration()
                configuration.mediaTypesRequiringUserActionForPlayback = .all
                let view = WKWebView(frame: .zero, configuration: configuration)
                view.navigationDelegate = self; view.uiDelegate = self
                webView = view; addSubview(view, positioned: .below, relativeTo: title)
                view.setAccessibilityLabel(L("Webpage"))
            }
        }
        // Restoring a hidden board at login must not load remote pages.
        if line.revealed, let webView, loadedURL == nil {
            loadedURL = url; webView.load(URLRequest(url: url))
        }
        for button in [back, forward, reload] { button.isHidden = card.kind != .webpage }
        back.isEnabled = webView?.canGoBack ?? false; forward.isEnabled = webView?.canGoForward ?? false
        if shown && !line.revealed { pause() }
        shown = line.revealed
        needsLayout = true
        if line.revealed, line.mediaFocusRequest == card.id {
            DispatchQueue.main.async { [weak self, weak line] in
                guard let self, let line, line.revealed, line.mediaFocusRequest == card.id else { return }
                self.layoutSubtreeIfNeeded()
                self.scrollToVisible(self.bounds)
                if self.window?.isVisible == true { line.mediaFocusRequest = nil }
            }
        }
    }

    override func layout() {
        super.layout()
        let buttons = webView == nil ? [external, remove] : [back, forward, reload, external, remove]
        let start = bounds.width - CGFloat(buttons.count) * 26 - 8
        title.frame = NSRect(x: 12, y: 10, width: max(0, start - 18), height: 18)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: start + CGFloat(index) * 26, y: 6, width: 24, height: 26)
        }
        let viewport = NSRect(x: 0, y: 38, width: bounds.width, height: max(0, bounds.height - 60))
        playerView?.frame = viewport; webView?.frame = viewport
        status.frame = NSRect(x: 16, y: viewport.midY - 24, width: max(0, bounds.width - 32), height: 48)
        progress.frame = NSRect(x: 12, y: bounds.height - 20, width: 14, height: 14)
    }

    func pause() {
        if let player = playerView?.player { player.pause(); onTime(player.currentTime().seconds) }
        webView?.pauseAllMediaPlayback(completionHandler: nil)
    }
    func dispose() {
        pause()
        observation = nil
        if let timeObserver, let player = playerView?.player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playerView?.player = nil; playerView?.removeFromSuperview(); playerView = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        webView?.removeFromSuperview(); webView = nil
        cardID = nil; loadedURL = nil
    }
    private func showFailure(_ message: String) {
        progress.stopAnimation(nil)
        status.stringValue = message; status.isHidden = false
    }
    @objc private func removeCard() { dispose(); onRemove() }
    @objc private func openExternal() { pause(); if let currentURL { NSWorkspace.shared.open(currentURL) } }
    @objc private func goBack() { webView?.goBack() }
    @objc private func goForward() { webView?.goForward() }
    @objc private func reloadContent() { status.isHidden = true; webView?.reload() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        status.isHidden = true; progress.startAnimation(nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress.stopAnimation(nil)
        if let url = webView.url, MediaImport.webpageURL(url.absoluteString) != nil {
            currentURL = url; title.stringValue = url.host ?? url.absoluteString; title.toolTip = url.absoluteString
            onURL(url)
        }
        back.isEnabled = webView.canGoBack; forward.isEnabled = webView.canGoForward
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showFailure(L("Could not load webpage")) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showFailure(L("Could not load webpage")) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showFailure(L("Could not load webpage")) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url, MediaImport.webpageURL(url.absoluteString) != nil else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, MediaImport.webpageURL(url.absoluteString) != nil { webView.load(URLRequest(url: url)) }
        return nil
    }
}
