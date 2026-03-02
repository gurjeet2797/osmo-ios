import Foundation

// MARK: - Markdown AST

enum MarkdownSpan: Sendable, Equatable {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
}

enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph([MarkdownSpan])
    case bulletList([[MarkdownSpan]])
    case numberedList([[MarkdownSpan]])
    case codeBlock(language: String?, code: String)
    case divider
}

// MARK: - Parser

enum MarkdownParser {

    static func parse(_ input: String) -> [MarkdownBlock] {
        let lines = input.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Divider: --- or *** or ___
            if trimmed.count >= 3, Set(trimmed).count == 1, ["-", "*", "_"].contains(trimmed.first) {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Heading: # text
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i += 1
                continue
            }

            // Code fence: ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language = lang.isEmpty ? nil : lang
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Bullet list: - or * at start
            if isBulletLine(trimmed) {
                var items: [[MarkdownSpan]] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isBulletLine(l) else { break }
                    let content = String(l.dropFirst(2))
                    items.append(parseInlineSpans(content))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list: 1. at start
            if isNumberedLine(trimmed) {
                var items: [[MarkdownSpan]] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isNumberedLine(l) else { break }
                    let dotIndex = l.firstIndex(of: ".")!
                    let afterDot = l[l.index(after: dotIndex)...]
                    let content = afterDot.trimmingCharacters(in: .whitespaces)
                    items.append(parseInlineSpans(content))
                    i += 1
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Paragraph (may span multiple non-blank lines)
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || isBulletLine(t) || isNumberedLine(t) {
                    break
                }
                paraLines.append(t)
                i += 1
            }
            let fullText = paraLines.joined(separator: " ")
            blocks.append(.paragraph(parseInlineSpans(fullText)))
        }

        return blocks
    }

    // MARK: - Inline span parsing

    static func parseInlineSpans(_ text: String) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            // Bold: **text**
            if remaining.hasPrefix("**") {
                if let end = remaining.dropFirst(2).range(of: "**") {
                    let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound])
                    spans.append(.bold(content))
                    remaining = remaining[end.upperBound...]
                    continue
                }
            }
            // Italic: *text* (not **)
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**") {
                let after = remaining.dropFirst(1)
                if let end = after.range(of: "*") {
                    let content = String(after[after.startIndex..<end.lowerBound])
                    if !content.isEmpty {
                        spans.append(.italic(content))
                        remaining = after[end.upperBound...]
                        continue
                    }
                }
            }
            // Inline code: `text`
            if remaining.hasPrefix("`"), !remaining.hasPrefix("```") {
                let after = remaining.dropFirst(1)
                if let end = after.range(of: "`") {
                    let content = String(after[after.startIndex..<end.lowerBound])
                    spans.append(.code(content))
                    remaining = after[end.upperBound...]
                    continue
                }
            }

            // Plain text: consume until next special char
            var plain = ""
            while !remaining.isEmpty {
                let ch = remaining.first!
                if ch == "*" || ch == "`" {
                    break
                }
                plain.append(ch)
                remaining = remaining.dropFirst(1)
            }
            if !plain.isEmpty {
                spans.append(.text(plain))
            }
        }

        return spans.isEmpty ? [.text(text)] : spans
    }

    /// Strip all markdown markers from text for plain display (e.g. HomeView typewriter).
    static func stripMarkdown(_ text: String) -> String {
        var result = text
        // Remove headings
        result = result.replacingOccurrences(
            of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
        // Remove bold/italic markers
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        // Single * for italic — be careful not to strip bullet points
        result = result.replacingOccurrences(
            of: #"(?<!\n)(?<![- ])\*([^*\n]+)\*"#, with: "$1", options: .regularExpression)
        // Remove inline code backticks
        result = result.replacingOccurrences(
            of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        // Remove code fences
        result = result.replacingOccurrences(
            of: #"```[a-zA-Z]*\n?"#, with: "", options: .regularExpression)
        return result
    }

    // MARK: - Line-type detection

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        let text = String(line.dropFirst(level + 1))
        return .heading(level: level, text: text)
    }

    private static func isBulletLine(_ line: String) -> Bool {
        (line.hasPrefix("- ") || line.hasPrefix("* ")) && line.count > 2
    }

    private static func isNumberedLine(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return false }
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }
}
