import AppKit
import QuartzCore

/// A discarded image falling below the line, drawn over the screen.
@MainActor
final class FallingCard {

    private let window: NSWindow
    private let container = CALayer()
    private let glass = CALayer()
    private let edge = CAGradientLayer()
    private let edgeMask = CAShapeLayer()
    private let photo = CALayer()
    private let clip = CAGradientLayer()

    private let to: CGRect
    private let tilt: CGFloat
    private let duration: CFTimeInterval = 0.55
    private var start: CFTimeInterval = 0
    private var timer: Timer?
    private var completion: () -> Void = {}

    private static var current: [FallingCard] = []

    /// A discarded card falling off the line, drawn over the whole screen so
    /// it is never cut by the line's strip. Same motion as the app always had:
    /// 520 points down, tilting further, fading, 0.55 s ease in.
    static func fall(image: CGImage, card: CGRect, tilt: CGFloat, on screen: NSScreen) {
        let flight = FallingCard(image: image, card: card, tilt: tilt, screen: screen)
        current.append(flight)
        flight.completion = { [weak flight] in current.removeAll { $0 === flight } }
        flight.run()
    }

    private init(image: CGImage, card: CGRect, tilt: CGFloat, screen: NSScreen) {
        self.to = card
        self.tilt = tilt
        window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = LinePanel.overlayBehavior

        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        window.contentView = host
        let scale = screen.backingScaleFactor

        container.anchorPoint = CGPoint(x: 0.5, y: 1)   // the card's top center
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.24
        container.shadowRadius = 10
        container.shadowOffset = CGSize(width: 0, height: -5)

        glass.backgroundColor = NSColor(white: 0.97, alpha: 0.72).cgColor
        edge.colors = [NSColor(white: 1, alpha: 0.9).cgColor, NSColor(white: 1, alpha: 0.25).cgColor]
        edge.startPoint = CGPoint(x: 0.5, y: 1); edge.endPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.fillColor = nil
        edgeMask.strokeColor = NSColor.black.cgColor
        edgeMask.lineWidth = 1.5
        edge.mask = edgeMask

        photo.contents = image
        photo.contentsGravity = .resizeAspectFill
        photo.masksToBounds = true
        photo.contentsScale = scale

        clip.colors = [NSColor(white: 0.70, alpha: 1).cgColor, NSColor(white: 0.93, alpha: 1).cgColor,
                       NSColor(white: 0.82, alpha: 1).cgColor, NSColor(white: 0.62, alpha: 1).cgColor]
        clip.locations = [0, 0.35, 0.65, 1]
        clip.startPoint = CGPoint(x: 0, y: 0.5); clip.endPoint = CGPoint(x: 1, y: 0.5)
        clip.cornerRadius = 3.5
        clip.borderColor = NSColor(white: 1, alpha: 0.7).cgColor
        clip.borderWidth = 0.6

        for layer in [container, glass, edge, photo, clip] as [CALayer] { layer.contentsScale = scale }
        container.addSublayer(glass)
        container.addSublayer(photo)
        container.addSublayer(edge)
        container.addSublayer(clip)
        host.layer?.addSublayer(container)
    }

    private func run() {
        layOutCard()
        updateFall(0)
        window.orderFrontRegardless()
        start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let k = min(1, (CACurrentMediaTime() - start) / duration)
        updateFall(k)
        guard k >= 1 else { return }
        timer?.invalidate()
        timer = nil
        completion()
        window.orderOut(nil)
    }

    private func updateFall(_ raw: Double) {
        let e = CGFloat(raw * raw * raw)
        let origin = window.frame.origin
        let angle = tilt + (tilt * 7 + 20) * e
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.position = CGPoint(x: to.midX - origin.x, y: to.maxY - origin.y - 520 * e)
        container.setAffineTransform(CGAffineTransform(rotationAngle: -angle * .pi / 180))
        container.opacity = Float(1 - e)
        CATransaction.commit()
    }

    private func layOutCard() {
        let w = to.width, h = to.height
        let origin = window.frame.origin
        let topX = to.midX - origin.x, topY = to.maxY - origin.y
        let inset: CGFloat = 4, radius: CGFloat = 16
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        container.position = CGPoint(x: topX, y: topY)
        // SwiftUI tilts clockwise for positive angles; Core Animation the other way.
        container.setAffineTransform(CGAffineTransform(rotationAngle: -tilt * .pi / 180))
        container.shadowPath = CGPath(roundedRect: container.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        glass.frame = container.bounds
        glass.cornerRadius = radius
        glass.opacity = 1
        edge.frame = container.bounds
        edgeMask.path = CGPath(roundedRect: container.bounds.insetBy(dx: 0.75, dy: 0.75),
                               cornerWidth: max(0, radius - 0.75), cornerHeight: max(0, radius - 0.75), transform: nil)
        edge.opacity = 1
        photo.frame = container.bounds.insetBy(dx: inset, dy: inset)
        photo.cornerRadius = max(0, radius - inset)
        // The clip grips the top edge: 26 points tall, 12 of them over the card.
        clip.frame = CGRect(x: w / 2 - 4.5, y: h - 12, width: 9, height: 26)
        clip.opacity = 1
        CATransaction.commit()
    }
}
