// Generates Sources/LookAwayCore/DailyVerses+All.swift from the reference
// list in scripts/daily-verse-references.txt, taking the exact wording of each
// verse from the Berean Standard Bible so nothing is quoted from memory.
//
//     swift scripts/generate-daily-verses.swift [path/to/bsb.txt]
//
// Without a path it downloads https://bereanbible.com/bsb.txt first. The BSB
// has been dedicated to the public domain, so the text may be bundled freely.
//
// A verse lifted out of its passage is tidied the way any quotation of it
// would be, without changing a word: a quotation mark the cut leaves open is
// closed and one it leaves stray is dropped, the first letter is capitalized,
// a verse that stops mid-sentence ends in an ellipsis, and "Selah", a musical
// direction, is left out. bsb.txt runs a psalm's heading into verse 1, so a
// line can name where the verse itself starts:
//
//     Psalm 23:1 | The LORD is my shepherd
//
// The list is rejected, with every problem reported at once, when a reference
// is malformed, unknown or repeated, when a start phrase isn't in its verse,
// or when a verse would not suit the popup: longer than it can show, a nested
// ‘quotation’ left open, or a psalm heading still in it.

import Foundation

let maxLength = 280
let minimumCount = 365
let sourceURL = URL(string: "https://bereanbible.com/bsb.txt")!

let scriptsDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptsDirectory.deletingLastPathComponent()
let referencesFile = scriptsDirectory.appendingPathComponent("daily-verse-references.txt")
let outputFile = repoRoot.appendingPathComponent("Sources/LookAwayCore/DailyVerses+All.swift")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - The Bible text

/// Every verse, keyed the way bsb.txt writes it: "Psalm 121:1".
func loadBible() -> [String: String] {
    let data: Data
    do {
        if CommandLine.arguments.count > 1 {
            data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        } else {
            print("Downloading \(sourceURL.absoluteString)…")
            data = try Data(contentsOf: sourceURL)
        }
    } catch {
        fail("Could not read the BSB text: \(error.localizedDescription)")
    }
    guard let text = String(data: data, encoding: .utf8) else { fail("The BSB text is not UTF-8.") }

    var verses: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else { continue }
        verses[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces)
    }
    return verses
}

// MARK: - The reference list

struct Reference {
    let book: String
    let chapter: Int
    let first: Int
    let last: Int
    /// Where the verse's own text begins, for a psalm whose heading comes first.
    var start: String?

    /// "Lamentations 3:22–23", with an en dash for a range.
    var display: String {
        first == last ? "\(book) \(chapter):\(first)" : "\(book) \(chapter):\(first)–\(last)"
    }

    var keys: [String] { (first...last).map { "\(book) \(chapter):\($0)" } }
}

/// "Book C:V" or "Book C:V-W", with the book spelled as bsb.txt spells it,
/// optionally followed by "| start phrase".
func parse(_ entry: String) -> Reference? {
    let parts = entry.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let line = parts[0]
    guard let space = line.lastIndex(of: " ") else { return nil }
    let book = String(line[..<space])
    let numbers = line[line.index(after: space)...].split(separator: ":")
    guard numbers.count == 2, let chapter = Int(numbers[0]) else { return nil }
    let verses = numbers[1].split(separator: "-")
    guard let first = verses.first.flatMap({ Int($0) }) else { return nil }
    let last = verses.count == 2 ? Int(verses[1]) : first
    guard verses.count <= 2, let last, last >= first else { return nil }
    let start = parts.count == 2 && !parts[1].isEmpty ? parts[1] : nil
    return Reference(book: book, chapter: chapter, first: first, last: last, start: start)
}

func loadReferences() -> [String] {
    guard let text = try? String(contentsOf: referencesFile, encoding: .utf8) else {
        fail("Could not read \(referencesFile.path).")
    }
    return text.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

// MARK: - Tidying and checks

/// Closes a quotation the cut leaves open and drops a closing mark whose
/// opening fell before the cut. Words are untouched.
func balancingQuotes(_ text: String) -> String {
    var depth = 0
    var result = ""
    for character in text {
        if character == "“" { depth += 1 }
        if character == "”" {
            guard depth > 0 else { continue }
            depth -= 1
        }
        result.append(character)
    }
    return result + String(repeating: "”", count: depth)
}

/// Starts the excerpt with a capital and ends one that stops mid-sentence
/// with an ellipsis rather than a comma or a dash.
func trimmingEdges(_ text: String) -> String {
    var text = text.prefix(1).uppercased() + text.dropFirst()
    if let last = text.last, ",;:—".contains(last) {
        text.removeLast()
        text += "…"
    }
    return text
}

func withoutSelah(_ text: String) -> String {
    text.replacingOccurrences(of: #"\s*\bSelah\b"#, with: "", options: .regularExpression)
}

/// Why a verse would read badly on its own in the popup, if it would.
func problem(with text: String) -> String? {
    if text.count > maxLength { return "\(text.count) characters, over \(maxLength)" }
    // ’ doubles as the apostrophe, which is always followed by a letter.
    let characters = Array(text)
    let openingSingles = characters.filter { $0 == "‘" }.count
    let closingSingles = characters.indices.filter { index in
        characters[index] == "’" && !(characters.indices.contains(index + 1) && characters[index + 1].isLetter)
    }.count
    if openingSingles > closingSingles { return "a nested ‘quotation’ left open" }
    let headings = ["A Psalm", "A song", "A Song", "For the choirmaster", "Of David", "A Maskil", "A Miktam"]
    if let heading = headings.first(where: { text.contains($0) }) { return "contains \"\(heading)\"" }
    return nil
}

// MARK: - Generate

let bible = loadBible()
var errors: [String] = []
var seen: Set<String> = []
var entries: [(reference: String, text: String)] = []

for line in loadReferences() {
    guard let reference = parse(line) else {
        errors.append("\(line): not a reference like \"Psalm 121:1\" or \"Psalm 121:1-2\"")
        continue
    }
    guard seen.insert(reference.display).inserted else {
        errors.append("\(line): listed twice")
        continue
    }
    let verses = reference.keys.map { bible[$0] }
    guard verses.allSatisfy({ $0 != nil }) else {
        errors.append("\(line): not found in the BSB")
        continue
    }
    var text = verses.compactMap { $0 }.joined(separator: " ")
    if let start = reference.start {
        guard let range = text.range(of: start) else {
            errors.append("\(line): \"\(start)\" is not in the verse")
            continue
        }
        text = String(text[range.lowerBound...])
    }
    text = trimmingEdges(balancingQuotes(withoutSelah(text)))
    if let problem = problem(with: text) {
        errors.append("\(line): \(problem)")
        continue
    }
    entries.append((reference.display, text))
}

if entries.count < minimumCount {
    errors.append("Only \(entries.count) usable verses; a year needs at least \(minimumCount).")
}
if !errors.isEmpty {
    fail("The reference list needs fixing:\n" + errors.map { "  • \($0)" }.joined(separator: "\n"))
}

func literal(_ string: String) -> String {
    "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

let lines = entries.map { "        Verse(text: \(literal($0.text)), reference: \(literal($0.reference)))," }
let source = """
// Generated by scripts/generate-daily-verses.swift from
// scripts/daily-verse-references.txt. Do not edit by hand: change the list
// and run `make verses`.
//
// Scripture quotations are from the Berean Standard Bible (BSB), which has
// been dedicated to the public domain. https://berean.bible

extension DailyVerses {
    /// One verse for each day of the year, in the order the list gives them.
    public static let all: [Verse] = [
\(lines.joined(separator: "\n"))
    ]
}

"""

do {
    try source.write(to: outputFile, atomically: true, encoding: .utf8)
} catch {
    fail("Could not write \(outputFile.path): \(error.localizedDescription)")
}
print("Wrote \(entries.count) verses to \(outputFile.path).")
