import XCTest
@testable import MikanseiCore

final class NoteGuideTests: XCTestCase {
    func testBuiltInGuideNoteIsMarkdownNote() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let note = Entry.builtInGuideNote(now: now)
        XCTAssertEqual(note.kind, .note)
        XCTAssertEqual(note.title, "使用说明")
        XCTAssertEqual(note.category, "帮助")
        XCTAssertTrue(note.body.contains("# "))
        XCTAssertTrue(note.body.contains("**"))
        XCTAssertEqual(note.createdAt, now)
        XCTAssertEqual(note.updatedAt, now)
        // 归档校验拒绝空标题与无效条目，内置笔记必须能原样过检。
        XCTAssertNoThrow(try EntryArchive.decode(try EntryArchive(entries: [note]).encoded()))
    }

    func testNoteMarkdownLineParsing() {
        let lines = NoteMarkdown.lines("# 大标题\n## 中标题\n- 项目\n  - 缩进项目\n普通段落\n\n---")
        XCTAssertEqual(lines.map(\.kind), [.heading1, .heading2, .bullet, .bullet, .paragraph, .paragraph, .paragraph])
        XCTAssertEqual(lines.map(\.text), ["大标题", "中标题", "项目", "缩进项目", "普通段落", "", "---"])
    }

    func testNoteMarkdownInlineBoldConvertsToAttributedString() throws {
        let line = NoteMarkdown.lines("支持 **Markdown** 与 `code` 预览")[0]
        XCTAssertEqual(line.kind, .paragraph)
        let attributed = try AttributedString(markdown: line.text,
                                              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        XCTAssertTrue(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertEqual(String(attributed.characters), "支持 Markdown 与 code 预览")
    }
}
