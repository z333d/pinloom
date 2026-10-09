// Optional original Pinloom disk image background. Copyright (c) 2026 z333d.
// The headless packaging script does not configure Finder window appearance.
import AppKit
let output = CommandLine.arguments.dropFirst().first ?? "background.png"
let scale = Double(CommandLine.arguments.dropFirst(2).first ?? "1") ?? 1
let size = NSSize(width: 600, height: 380)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.98, green: 0.96, blue: 0.90, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let style = NSMutableParagraphStyle(); style.alignment = .center
("Drag Pinloom to Applications" as NSString).draw(in: NSRect(x: 0, y: 52, width: 600, height: 22),
    withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
