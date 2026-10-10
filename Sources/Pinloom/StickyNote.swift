import AppKit

struct NoteTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var completed = false
}

struct StickyNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var tasks: [NoteTask] = []
    var width: Double = Double(CardSizing.defaultNoteSize.width)
    var height: Double = Double(CardSizing.defaultNoteSize.height)
    var x: Double?
    var y: Double?

    var plainText: String {
        ([text] + tasks.map { "\($0.completed ? "[x]" : "[ ]") \($0.text)" })
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum NoteLayout {
    static func size(_ note: StickyNote, available: CGSize) -> CGSize {
        CardSizing.noteSize(CGSize(width: note.width, height: note.height), available: available)
    }
    static func position(_ note: StickyNote, defaultX: CGFloat, size: CGSize, width: CGFloat, height: CGFloat) -> CGPoint {
        let half = size.width / 2 + 18
        let x = max(half, min(width - half, note.x.map { CGFloat($0) } ?? defaultX))
        let top = max(0, Layout.ropeY(x: x, width: width) - Layout.pinAbove)
        return CGPoint(x: x, y: max(top, min(max(top, height - size.height - 40), note.y.map { CGFloat($0) } ?? top)))
    }
}
