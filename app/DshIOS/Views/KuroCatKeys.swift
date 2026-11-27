import Foundation

/// Row order matches the key atlases rendered from the KuroCat keyboard.
struct KuroCatKey: Equatable {
    static let rows = [
        ["ESC", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "⌫"],
        ["⇥", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "↵"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "↑"],
        ["space", "←", "↓", "→"]
    ]
    static let frames = 6
    private static let shifted: [Character: String] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/"
    ]

    let row: Int
    let slot: Int
    var label: String { Self.rows[row][slot] == "space" ? "SPACE" : Self.rows[row][slot] }

    init?(legend: String) {
        for (row, legends) in Self.rows.enumerated() {
            if let slot = legends.firstIndex(of: legend) {
                self.row = row
                self.slot = slot
                return
            }
        }
        return nil
    }

    init?(character: Character) {
        guard character.isASCII else { return nil }
        switch character {
        case " ": self.init(legend: "space")
        case "\r", "\n": self.init(legend: "↵")
        case "\t": self.init(legend: "⇥")
        default: self.init(legend: Self.shifted[character] ?? String(character).uppercased())
        }
    }

    /// Compare an editor change at either end or in the middle of a draft. Multi-character
    /// substitutions (candidate commits, dictation, paste) do not imply a specific key.
    static func singleEdit(from previous: String, to next: String) -> Self? {
        let delta = next.count - previous.count
        guard delta == 1 || delta == -1 else { return nil }
        let longer = delta == 1 ? next : previous
        let shorter = delta == 1 ? previous : next
        var position = longer.startIndex
        var other = shorter.startIndex
        while other != shorter.endIndex, longer[position] == shorter[other] {
            longer.formIndex(after: &position)
            shorter.formIndex(after: &other)
        }
        let changed = longer[position]
        guard longer[longer.index(after: position)...] == shorter[other...] else { return nil }
        return delta == 1 ? Self(character: changed) : Self(legend: "⌫")
    }

    /// Composition is only informative when the IME exposes a simple ASCII letter edit.
    static func composition(from previous: String, to next: String) -> Self? {
        guard previous.utf8.allSatisfy(isPinyinByte), next.utf8.allSatisfy(isPinyinByte),
              !next.isEmpty else { return nil }
        return singleEdit(from: previous, to: next)
    }

    private static func isPinyinByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 39
    }
}

struct KuroCatStroke: Equatable {
    var revision = 0
    var key: KuroCatKey?
}
