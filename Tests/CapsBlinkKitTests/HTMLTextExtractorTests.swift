import XCTest
@testable import CapsBlinkKit

final class HTMLTextExtractorTests: XCTestCase {
    private let extractor = HTMLTextExtractor()

    func testStripsScriptsStylesAndComments() {
        let html = """
        <html><head><title>Live: 2-1</title><style>body { color: red }</style></head>
        <body>
        <script type="text/javascript">var secret = "should not appear";</script>
        <!-- hidden comment -->
        <p>Arsenal 2 - 1 Chelsea</p>
        <noscript>Enable JS</noscript>
        </body></html>
        """
        let text = extractor.text(fromHTML: html)
        XCTAssertTrue(text.contains("Arsenal 2 - 1 Chelsea"))
        XCTAssertTrue(text.contains("Live: 2-1"), "title should be preserved")
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("color: red"))
        XCTAssertFalse(text.contains("hidden comment"))
        XCTAssertFalse(text.contains("Enable JS"))
    }

    func testBlockTagsProduceLineBreaks() {
        let html = "<div>First</div><div>Second</div><ul><li>Item A</li><li>Item B</li></ul>"
        let text = extractor.text(fromHTML: html)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines, ["First", "Second", "Item A", "Item B"])
    }

    func testTableCellsStayOnOneLine() {
        let html = "<table><tr><td>Team A</td><td>2</td></tr><tr><td>Team B</td><td>1</td></tr></table>"
        let text = extractor.text(fromHTML: html)
        XCTAssertTrue(text.contains("Team A 2"))
        XCTAssertTrue(text.contains("Team B 1"))
    }

    func testDecodesEntities() {
        let html = "<p>Fish &amp; Chips &lt;3 &#8212; caf&#xE9; &nbsp; score</p>"
        let text = extractor.text(fromHTML: html)
        XCTAssertTrue(text.contains("Fish & Chips <3 — café score"))
    }

    func testCollapsesWhitespace() {
        let html = "<p>  lots   of\n\n\n   space  </p><p></p><p>next</p>"
        let text = extractor.text(fromHTML: html)
        XCTAssertEqual(text, "lots of\nspace\nnext")
    }

    func testTruncationCutsAtLineBoundary() {
        let longLine = String(repeating: "a", count: 50)
        let html = (0..<100).map { "<p>line \($0) \(longLine)</p>" }.joined()
        let extractor = HTMLTextExtractor(maximumCharacters: 500)
        let text = extractor.text(fromHTML: html)
        XCTAssertLessThanOrEqual(text.count, 500)
        let lastLine = text.components(separatedBy: "\n").last ?? ""
        XCTAssertTrue(lastLine.hasSuffix(longLine), "must cut at a line boundary, not mid-line")
    }

    func testInlineTagsDoNotBreakWords() {
        let html = "<p><b>2</b>:<i>1</i> final</p>"
        let text = extractor.text(fromHTML: html)
        XCTAssertTrue(text.contains("2:1 final"))
    }
}
