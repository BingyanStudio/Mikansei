import Foundation

/// 笔记正文的极简 Markdown 行级解析：只认 “# 大标题 / ## 中标题 / - 项目符号”，
/// 其余按普通段落；加粗、斜体、行内代码交给 AttributedString 的行内解释。
public enum NoteMarkdown {
    public enum LineKind: Equatable {
        case heading1, heading2, bullet, paragraph
    }

    public struct Line: Equatable {
        public let kind: LineKind
        public let text: String
        public init(kind: LineKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// 按行拆分正文。前缀匹配忽略行首空白，缩进的 “- ” 也渲染为项目符号；空行保留为空段落。
    public static func lines(_ body: String) -> [Line] {
        body.components(separatedBy: .newlines).map { raw in
            let content = raw.drop(while: { $0 == " " || $0 == "\t" })
            if content.hasPrefix("# ") { return Line(kind: .heading1, text: String(content.dropFirst(2))) }
            if content.hasPrefix("## ") { return Line(kind: .heading2, text: String(content.dropFirst(3))) }
            if content.hasPrefix("- ") { return Line(kind: .bullet, text: String(content.dropFirst(2))) }
            return Line(kind: .paragraph, text: raw)
        }
    }

    /// 行内 Markdown 转 AttributedString；解析失败时按纯文本原样返回。
    public static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
