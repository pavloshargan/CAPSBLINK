import Foundation

/// Converts raw HTML into compact plain text: strips scripts, styles and
/// markup, decodes entities and collapses whitespace, so downstream change
/// detection and the LLM only ever see human-visible content.
///
/// This is a deliberately lightweight, dependency-free extractor. It does not
/// build a DOM; for the "did visible text change" use case a tag stripper is
/// robust enough and trivially testable.
public struct HTMLTextExtractor: Sendable {
    /// Maximum length of the extracted text, cut at a line boundary.
    public var maximumCharacters: Int

    public init(maximumCharacters: Int = 60_000) {
        self.maximumCharacters = maximumCharacters
    }

    public func text(fromHTML html: String) -> String {
        var working = html

        // Keep the <title> — it often carries the headline state (e.g. a live score).
        let title = Self.firstMatch(of: Self.titleRegex, in: working).map(Self.decodeEntities)

        working = Self.replace(Self.commentRegex, in: working, with: " ")
        working = Self.replace(Self.opaqueContainerRegex, in: working, with: " ")
        working = Self.replace(Self.blockTagRegex, in: working, with: "\n")
        working = Self.replace(Self.cellTagRegex, in: working, with: " ")
        working = Self.replace(Self.anyTagRegex, in: working, with: "")
        working = Self.decodeEntities(working)
        working = Self.normalizeWhitespace(working)

        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            working = title + "\n" + working
        }
        return Self.truncateAtLineBoundary(working, limit: maximumCharacters)
    }

    // MARK: - Regexes

    private static let titleRegex = regex("<title[^>]*>(.*?)</title>")
    private static let commentRegex = regex("<!--.*?-->")
    /// Elements whose content is never user-visible text.
    private static let opaqueContainerRegex = regex(
        "<(script|style|noscript|template|svg|iframe|object|embed|canvas|audio|video|map|head)\\b[^>]*>.*?</\\1\\s*>"
    )
    /// Tags that visually separate content — replaced with newlines.
    private static let blockTagRegex = regex(
        "</?(p|div|br|hr|li|ul|ol|dl|dt|dd|tr|table|thead|tbody|tfoot|caption|h[1-6]|section|article|aside|header|footer|nav|main|blockquote|pre|form|fieldset|figure|figcaption|details|summary|option|address)\\b[^>]*>"
    )
    /// Table cells become spaces so "Team A | 2" stays on one line.
    private static let cellTagRegex = regex("</?(td|th)\\b[^>]*>")
    private static let anyTagRegex = regex("<[^>]{0,512}>")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; force-try is safe and loud in tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }

    private static func replace(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: template
        )
    }

    private static func firstMatch(of regex: NSRegularExpression, in string: String) -> String? {
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: string)
        else { return nil }
        return String(string[captured])
    }

    // MARK: - Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "plusmn": "±",
        "times": "×", "divide": "÷", "laquo": "«", "raquo": "»",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "bull": "•", "middot": "·", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
    ]

    private static let entityRegex = regex("&(#x?[0-9a-f]{1,8}|[a-z]{2,10});")

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var lastIndex = string.startIndex
        let nsRange = NSRange(string.startIndex..., in: string)
        entityRegex.enumerateMatches(in: string, range: nsRange) { match, _, _ in
            guard let match,
                  let whole = Range(match.range, in: string),
                  let bodyRange = Range(match.range(at: 1), in: string)
            else { return }
            let body = string[bodyRange].lowercased()
            var replacement: String?
            if body.hasPrefix("#x"), let code = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                replacement = String(Character(scalar))
            } else if body.hasPrefix("#"), let code = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(code) {
                replacement = String(Character(scalar))
            } else {
                replacement = namedEntities[body]
            }
            guard let replacement else { return }
            result += string[lastIndex..<whole.lowerBound]
            result += replacement
            lastIndex = whole.upperBound
        }
        result += string[lastIndex...]
        return result
    }

    // MARK: - Whitespace

    static func normalizeWhitespace(_ string: String) -> String {
        let lines = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func truncateAtLineBoundary(_ string: String, limit: Int) -> String {
        guard string.count > limit else { return string }
        let prefix = string.prefix(limit)
        if let lastNewline = prefix.lastIndex(of: "\n") {
            return String(prefix[..<lastNewline])
        }
        return String(prefix)
    }
}
