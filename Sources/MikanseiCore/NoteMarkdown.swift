import Foundation

/// A small, safe Markdown renderer for note previews. It keeps the source text
/// untouched; block parsing only changes how that text is displayed.
public enum NoteMarkdown {
    public enum LineKind: Equatable {
        case heading1, heading2, heading3, heading4, heading5, heading6
        case bullet, orderedList, blockquote, codeBlock, horizontalRule, paragraph
    }

    public struct Line: Equatable {
        public let kind: LineKind
        public let text: String
        /// Indentation depth for nested lists and quotes.
        public let depth: Int
        /// The displayed number for an ordered-list row.
        public let number: Int?

        public init(kind: LineKind, text: String, depth: Int = 0, number: Int? = nil) {
            self.kind = kind
            self.text = text
            self.depth = depth
            self.number = number
        }
    }

    /// Parses common block Markdown without rewriting the note body. HTML stays
    /// text in SwiftUI's Text view; fenced code is never parsed as Markdown.
    public static func lines(_ body: String) -> [Line] {
        let rawLines = body.components(separatedBy: .newlines)
        var result: [Line] = []
        var openFence: (character: Character, count: Int)?
        var codeLines: [String]?

        for raw in rawLines {
            let content = droppingIndent(raw)
            if let fence = openFence {
                if closesFence(content, fence: fence) {
                    openFence = nil
                    result.append(Line(kind: .codeBlock, text: codeLines?.joined(separator: "\n") ?? ""))
                    codeLines = nil
                } else {
                    codeLines?.append(raw)
                }
                continue
            }
            if let fence = openingFence(content) {
                openFence = fence
                codeLines = []
                continue
            }

            let indentation = indentationCount(raw)
            if let heading = heading(content) {
                result.append(Line(kind: heading.kind, text: heading.text))
            } else if isHorizontalRule(content) {
                result.append(Line(kind: .horizontalRule, text: ""))
            } else if let quote = blockquote(content) {
                result.append(Line(kind: .blockquote, text: quote.text, depth: quote.depth))
            } else if let bullet = unorderedItem(content) {
                result.append(Line(kind: .bullet, text: bullet, depth: indentation / 2))
            } else if let ordered = orderedItem(content) {
                result.append(Line(kind: .orderedList, text: ordered.text,
                                   depth: indentation / 2, number: ordered.number))
            } else {
                result.append(Line(kind: .paragraph, text: raw))
            }
        }
        if openFence != nil {
            result.append(Line(kind: .codeBlock, text: codeLines?.joined(separator: "\n") ?? ""))
        }
        return result
    }

    /// Inline emphasis, code and links are rendered by Foundation's Markdown
    /// parser. Image syntax is reduced to its alt text, and links with unsafe
    /// schemes are shown as plain text.
    public static func inline(_ text: String) -> AttributedString {
        let sanitized = sanitizeInline(text)
        guard var rendered = try? AttributedString(
            markdown: sanitized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(text)
        }
        let unsafeLinkRanges = rendered.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link else { return nil }
            let scheme = link.scheme?.lowercased()
            return scheme.map({ ["http", "https"].contains($0) }) == true && link.host != nil ? nil : run.range
        }
        for range in unsafeLinkRanges { rendered[range].link = nil }
        return rendered
    }

    private static func droppingIndent(_ raw: String) -> String {
        String(raw.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func indentationCount(_ raw: String) -> Int {
        raw.prefix(while: { $0 == " " || $0 == "\t" }).reduce(into: 0) { count, character in
            count += character == "\t" ? 2 : 1
        }
    }

    private static func heading(_ content: String) -> (kind: LineKind, text: String)? {
        let count = content.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), content.dropFirst(count).first?.isWhitespace == true else { return nil }
        let text = String(content.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        let kinds: [LineKind] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]
        return (kinds[count - 1], text)
    }

    private static func isHorizontalRule(_ content: String) -> Bool {
        let compact = content.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func blockquote(_ content: String) -> (depth: Int, text: String)? {
        var remainder = content[...]
        var depth = 0
        while remainder.first == ">" {
            depth += 1
            remainder = remainder.dropFirst()
            if remainder.first == " " || remainder.first == "\t" { remainder = remainder.dropFirst() }
        }
        guard depth > 0 else { return nil }
        return (depth, String(remainder))
    }

    private static func unorderedItem(_ content: String) -> String? {
        guard let marker = content.first, ["-", "*", "+"].contains(marker),
              content.dropFirst().first == " " || content.dropFirst().first == "\t" else { return nil }
        return String(content.dropFirst(2))
    }

    private static func orderedItem(_ content: String) -> (number: Int, text: String)? {
        let pattern = #"^(\d{1,9})[.)][ \t]+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let numberRange = Range(match.range(at: 1), in: content),
              let textRange = Range(match.range(at: 2), in: content),
              let number = Int(content[numberRange]) else { return nil }
        return (number, String(content[textRange]))
    }

    private static func openingFence(_ content: String) -> (character: Character, count: Int)? {
        guard let marker = content.first, marker == "\u{60}" || marker == "~" else { return nil }
        let count = content.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        return (marker, count)
    }

    private static func closesFence(_ content: String, fence: (character: Character, count: Int)) -> Bool {
        let count = content.prefix(while: { $0 == fence.character }).count
        guard count >= fence.count else { return false }
        return content.dropFirst(count).allSatisfy(\.isWhitespace)
    }

    private static func sanitizeInline(_ text: String) -> String {
        let pattern = #"(!?)\[([^\]\n]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let imageRange = Range(match.range(at: 1), in: result),
                  let labelRange = Range(match.range(at: 2), in: result),
                  let destinationRange = Range(match.range(at: 3), in: result) else { continue }
            let isImage = String(result[imageRange]) == "!"
            let label = String(result[labelRange])
            let destination = String(result[destinationRange])
            if isImage {
                result.replaceSubrange(fullRange, with: label)
            } else if !isSafeLink(destination) {
                result.replaceSubrange(fullRange, with: "\(label) (\(destination))")
            }
        }
        return result
    }

    private static func isSafeLink(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        return true
    }
}
