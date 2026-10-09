// Original Pinloom artwork, Copyright (c) 2026 z333d. MIT licensed.
// Usage: swift scripts/make-icon.swift output.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon.png"
let side = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let ink = color(0x203B3A), paper = color(0xFFF4D9), accent = color(0xF17C58)
let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200)
ink.setFill(); tile.fill()

// A folded note, held by one oversized diagonal pin. No upstream icon art.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.shadowBlurRadius = 32; shadow.shadowColor = .black.withAlphaComponent(0.22); shadow.set()
let note = NSBezierPath()
note.move(to: NSPoint(x: 276, y: 220)); note.line(to: NSPoint(x: 684, y: 220))
note.line(to: NSPoint(x: 792, y: 328)); note.line(to: NSPoint(x: 792, y: 712))
note.curve(to: NSPoint(x: 756, y: 748), controlPoint1: NSPoint(x: 792, y: 734), controlPoint2: NSPoint(x: 778, y: 748))
note.line(to: NSPoint(x: 276, y: 748))
note.curve(to: NSPoint(x: 240, y: 712), controlPoint1: NSPoint(x: 254, y: 748), controlPoint2: NSPoint(x: 240, y: 734))
note.line(to: NSPoint(x: 240, y: 256))
note.curve(to: NSPoint(x: 276, y: 220), controlPoint1: NSPoint(x: 240, y: 234), controlPoint2: NSPoint(x: 254, y: 220))
note.close(); paper.setFill(); note.fill()
NSGraphicsContext.restoreGraphicsState()
let fold = NSBezierPath(); fold.move(to: NSPoint(x: 684, y: 220))
fold.line(to: NSPoint(x: 684, y: 328)); fold.line(to: NSPoint(x: 792, y: 328)); fold.close()
color(0xD8CDB5).setFill(); fold.fill()

for (y, width) in [(442.0, 294.0), (350.0, 198.0)] {
    color(0xA7B5A5).setFill()
    NSBezierPath(roundedRect: NSRect(x: 314, y: y, width: width, height: 22), xRadius: 11, yRadius: 11).fill()
}
let stem = NSBezierPath(); stem.move(to: NSPoint(x: 445, y: 518)); stem.line(to: NSPoint(x: 660, y: 733))
stem.lineWidth = 30; stem.lineCapStyle = .round; accent.setStroke(); stem.stroke()
let pin = NSBezierPath(ovalIn: NSRect(x: 586, y: 652, width: 172, height: 172))
accent.setFill(); pin.fill()
color(0xFFC4A8).setFill()
NSBezierPath(ovalIn: NSRect(x: 612, y: 746, width: 45, height: 33)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
