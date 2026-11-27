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

}

/// The input method can rewrite syllable separators or deliver several letters in one update.
/// Compare only the letters in the marked text that the editor exposes.
struct KuroCatComposition {
    private var letters: [Character] = []

    mutating func update(_ text: String?) -> [KuroCatKey] {
        guard let text, !text.isEmpty else {
            letters.removeAll()
            return []
        }
        let compact = text.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
        // Some keyboards leave a selected word at the front of the marked range.
        let next = compact.reversed().prefix { character in
            character.isASCII && character.isLetter
        }.reversed()
        guard !next.isEmpty else {
            letters.removeAll()
            return []
        }
        let previous = letters
        letters = Array(String(next).lowercased())
        let prefix = zip(previous, letters).prefix { $0.0 == $0.1 }.count
        let oldTail = previous.dropFirst(prefix)
        let newTail = letters.dropFirst(prefix)
        let suffix = zip(oldTail.reversed(), newTail.reversed()).prefix { $0.0 == $0.1 }.count
        let inserted = newTail.dropLast(suffix)
        if inserted.isEmpty, oldTail.count - suffix == 1 {
            return KuroCatKey(legend: "⌫").map { [$0] } ?? []
        }
        return inserted.compactMap { KuroCatKey(character: $0) }
    }
}

struct KuroCatStroke: Equatable {
    private(set) var revision = 0
    private(set) var keys: [KuroCatKey] = []

    mutating func append(_ key: KuroCatKey) {
        revision &+= 1
        if keys.count == 64 { keys.removeFirst() }
        keys.append(key)
    }
}
