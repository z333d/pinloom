// Wrap an offscreen Pinloom render in a solid background for the README.
// Original documentation artwork, Copyright (c) 2026 z333d. MIT licensed.
// Usage: swift scripts/make-readme-art.swift input.png output.png
import AppKit
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, let image = NSImage(contentsOfFile: arguments[0]) else {
    fputs("Usage: swift scripts/make-readme-art.swift input.png output.png\n", stderr); exit(1)
}
let size = image.size
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.10, green: 0.15, blue: 0.15, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[1]))
