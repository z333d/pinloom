import AppKit

enum CardSizing {
    // Keep the original scale unit so existing manually resized images stay
    // the same size. New images start at a more readable presentation.
    static let defaultImageScale: CGFloat = 2.25
    static let minimumImageScale: CGFloat = 0.65
    static let defaultNoteSize = CGSize(width: 320, height: 280)
    static let minimumNoteSize = CGSize(width: 240, height: 220)

    static func maximumCardSize(available: CGSize) -> CGSize {
        CGSize(width: max(64, available.width * 0.85 - 40),
               height: max(40, available.height - 100))
    }

    static func imageScale(_ requested: CGFloat, image: CGSize, available: CGSize) -> CGFloat {
        let photo = PeggedView.photoSize(for: image)
        let maximum = maximumCardSize(available: available)
        let limit = min((maximum.width - Frame.inset * 2) / photo.width,
                        (maximum.height - Frame.inset * 2) / photo.height)
        return min(max(minimumImageScale, requested), max(0.1, limit))
    }

    static func noteSize(_ requested: CGSize, available: CGSize) -> CGSize {
        let maximum = maximumCardSize(available: available)
        return CGSize(width: min(maximum.width, max(minimumNoteSize.width, requested.width)),
                      height: min(maximum.height, max(minimumNoteSize.height, requested.height)))
    }

    static func thumbnailPixels(scale: CGFloat) -> Int {
        scale > 3 ? 3072 : (scale > 1 ? 960 : 480)
    }
}
