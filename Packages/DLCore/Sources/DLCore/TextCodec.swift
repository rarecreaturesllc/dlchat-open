import Foundation

public enum TextCodecError: Error, Equatable {
    case emptyMessage
    case truncated
}

/// Static Huffman coding of lowercase English (blueprint section 3, text coding).
///
/// Part of the wire format. Tokens, in this order: END, SPELL, NUM, STOP, letters
/// a-z, digits 0-9, then each dictionary word in file order. Weights are fixed
/// integers, and ties break on token order, so every phone builds the same code.
/// A dictionary word is one token. Any other letter run is SPELL, its letters,
/// STOP. A digit run is NUM, its digits, STOP. The message ends with END.
/// An apostrophe between letters (' or ’) keeps a contraction together as one
/// run ("i'm"); if that contraction is not a dictionary word it is split at the
/// apostrophe and each part is coded as above.
public enum TextCodec {
    static let endToken = 0
    static let spellToken = 1
    static let numToken = 2
    static let stopToken = 3
    static let letterBase = 4
    static let digitBase = 30
    static let wordBase = 40

    static let resourceURL = Bundle.module.url(forResource: "dictionary", withExtension: "txt")

    /// Dictionary words, most common first. Crashes at launch if missing.
    public static let dictionary: [String] = {
        guard let url = resourceURL,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("dictionary.txt missing from DLCore resources") }
        return text.split(separator: "\n").map(String.init)
    }()

    private static let wordTokens: [String: Int] = {
        Dictionary(uniqueKeysWithValues: dictionary.enumerated().map { ($1, wordBase + $0) })
    }()

    /// Canonical form that round trips: lowercase, split on anything that is not
    /// a letter or digit (except a dictionary contraction's apostrophe), and split
    /// where letters meet digits. Words joined by one space.
    public static func normalize(_ text: String) -> String {
        runs(in: text).map(\.text).joined(separator: " ")
    }

    /// Words that are not in the dictionary and so are spelled letter by letter, each
    /// costing several spoken words. Shown while typing so a cheaper word can be picked.
    public static func spelledWords(in text: String) -> [String] {
        var seen = Set<String>()
        return runs(in: text).filter { !$0.isDigits && wordTokens[$0.text] == nil && seen.insert($0.text).inserted }.map(\.text)
    }

    /// How many words (runs) `text` codes as.
    static func runCount(in text: String) -> Int { runs(in: text).count }

    public static func encode(_ text: String) throws -> Bits {
        let items = runs(in: text)
        guard !items.isEmpty else { throw TextCodecError.emptyMessage }
        var out = Bits()
        for item in items {
            if item.isDigits {
                put(numToken, into: &out)
                for ch in item.text.utf8 { put(digitBase + Int(ch - 48), into: &out) }
                put(stopToken, into: &out)
            } else if let token = wordTokens[item.text] {
                put(token, into: &out)
            } else {
                put(spellToken, into: &out)
                for ch in item.text.utf8 { put(letterBase + Int(ch - 97), into: &out) }
                put(stopToken, into: &out)
            }
        }
        put(endToken, into: &out)
        return out
    }

    /// Reads tokens until END; anything after it (padding) is ignored.
    public static func decode(_ bits: Bits) throws -> String {
        var end = 0
        return try decode(bits, end: &end)
    }

    /// As `decode`, and sets `end` to the bit just after END, where padding (or a `ChatCarry` frame) starts.
    public static func decode(_ bits: Bits, end: inout Int) throws -> String {
        var position = 0
        defer { end = position }
        var words: [String] = []
        while true {
            let token = try next(in: bits, at: &position)
            switch token {
            case endToken:
                guard !words.isEmpty else { throw TextCodecError.emptyMessage }
                return words.joined(separator: " ")
            case spellToken, numToken:
                var run = ""
                while true {
                    let inner = try next(in: bits, at: &position)
                    if inner == stopToken { break }
                    let offset = token == spellToken ? inner - letterBase : inner - digitBase
                    let limit = token == spellToken ? 26 : 10
                    guard (0..<limit).contains(offset) else { throw TextCodecError.truncated }
                    run.append(Character(UnicodeScalar(UInt8((token == spellToken ? 97 : 48) + offset))))
                }
                guard !run.isEmpty else { throw TextCodecError.truncated }
                words.append(run)
            case wordBase...:
                words.append(dictionary[token - wordBase])
            default:
                throw TextCodecError.truncated
            }
        }
    }

    // MARK: Runs

    private struct Run {
        let text: String
        let isDigits: Bool
    }

    private static func runs(in text: String) -> [Run] {
        var result: [Run] = []
        var current = ""
        var digits = false
        func flush() {
            if current.hasSuffix("'") { current.removeLast() }
            if current.contains("'") && wordTokens[current] == nil {
                // Not a known contraction: code its parts separately, as before contractions existed.
                result += current.split(separator: "'").map { Run(text: String($0), isDigits: false) }
            } else if !current.isEmpty {
                result.append(Run(text: current, isDigits: digits))
            }
            current = ""
        }
        for scalar in text.lowercased().unicodeScalars {
            let isLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            let isApostrophe = scalar == "'" || scalar == "\u{2019}"
            if isApostrophe && !current.isEmpty && !digits && !current.hasSuffix("'") {
                current.append("'")
                continue
            }
            guard isLetter || isDigit else { flush(); continue }
            if !current.isEmpty && digits != isDigit { flush() }
            digits = isDigit
            current.unicodeScalars.append(scalar)
        }
        flush()
        return result
    }

    // MARK: Huffman code

    private struct Node {
        var weight: Int
        var left: Int
        var right: Int
        var token: Int  // -1 for inner nodes
    }

    private static func weight(of token: Int) -> Int {
        switch token {
        case endToken: return 300_000
        case spellToken: return 20_000
        case numToken: return 5_000
        case stopToken: return 20_000
        // Spelled letters by English letter frequency (per 10,000), so common letters get shorter codes.
        case letterBase..<digitBase: return letterFrequency[token - letterBase] * 78 / 10
        case digitBase..<wordBase: return 4_000
        default: return 1_000_000 / (token - wordBase + 2)
        }
    }

    private static let letterFrequency = [
        817, 149, 278, 425, 1270, 223, 202, 609, 697, 15, 77, 403, 241,
        675, 751, 193, 10, 599, 633, 906, 276, 98, 236, 15, 197, 7,
    ]  // a...z

    private static let tokenCount = wordBase + dictionary.count

    /// Tree nodes; the root is the last one.
    private static let nodes: [Node] = {
        var all = (0..<tokenCount).map { Node(weight: weight(of: $0), left: -1, right: -1, token: $0) }
        var open = Array(0..<tokenCount)
        while open.count > 1 {
            // Two lightest; ties go to the lower node index (older node).
            open.sort { (all[$0].weight, $0) < (all[$1].weight, $1) }
            let a = open.removeFirst()
            let b = open.removeFirst()
            all.append(Node(weight: all[a].weight + all[b].weight, left: a, right: b, token: -1))
            open.append(all.count - 1)
        }
        return all
    }()

    /// Code for each token: bit pattern and length.
    private static let codes: [(value: UInt64, width: Int)] = {
        var table = [(value: UInt64, width: Int)](repeating: (0, 0), count: tokenCount)
        var stack: [(node: Int, value: UInt64, width: Int)] = [(nodes.count - 1, 0, 0)]
        while let item = stack.popLast() {
            let node = nodes[item.node]
            if node.token >= 0 {
                table[node.token] = (item.value, item.width)
            } else {
                stack.append((node.left, item.value << 1, item.width + 1))
                stack.append((node.right, (item.value << 1) | 1, item.width + 1))
            }
        }
        return table
    }()

    private static func put(_ token: Int, into bits: inout Bits) {
        let code = codes[token]
        bits.append(code.value, width: code.width)
    }

    private static func next(in bits: Bits, at position: inout Int) throws -> Int {
        var node = nodes.count - 1
        while nodes[node].token < 0 {
            guard position < bits.count else { throw TextCodecError.truncated }
            node = bits.bit(at: position) ? nodes[node].right : nodes[node].left
            position += 1
        }
        return nodes[node].token
    }
}
