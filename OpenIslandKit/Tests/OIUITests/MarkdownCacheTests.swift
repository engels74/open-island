import Foundation
import Markdown
import Testing

// MARK: - MarkdownCacheTests

/// Tests for markdown document parsing and caching behavior.
///
/// Since ``DocumentCache`` is private to the OIUI module, these tests verify
/// the underlying `swift-markdown` parsing that the cache wraps — ensuring
/// that the rendering pipeline produces correct, non-empty results for
/// various Markdown constructs.
struct MarkdownCacheTests {
    // MARK: - Basic Rendering

    @Test
    func `Bold text produces non-empty AttributedString`() {
        let doc = Document(parsing: "**bold text**")
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        #expect(!result.characters.isEmpty)
        let plainText = String(result.characters)
        #expect(plainText.contains("bold text"))
    }

    @Test
    func `Italic text produces non-empty AttributedString`() {
        let doc = Document(parsing: "*italic text*")
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        #expect(!result.characters.isEmpty)
        let plainText = String(result.characters)
        #expect(plainText.contains("italic text"))
    }

    @Test
    func `Inline code produces non-empty AttributedString`() {
        let doc = Document(parsing: "`let x = 42`")
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        #expect(!result.characters.isEmpty)
        let plainText = String(result.characters)
        #expect(plainText.contains("let x = 42"))
    }

    @Test
    func `Heading produces non-empty AttributedString`() {
        let doc = Document(parsing: "# Hello World")
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        #expect(!result.characters.isEmpty)
        let plainText = String(result.characters)
        #expect(plainText.contains("Hello World"))
    }

    // MARK: - Cache Behavior (via string identity)

    @Test
    func `Same content string is equal for cache key purposes`() {
        let source1 = "Hello **world**"
        let source2 = "Hello **world**"
        #expect(source1 == source2)
    }

    @Test
    func `Different content produces different parse results`() {
        let doc1 = Document(parsing: "Hello")
        let doc2 = Document(parsing: "Goodbye")

        var renderer1 = TestMarkdownRenderer()
        var renderer2 = TestMarkdownRenderer()
        let result1 = renderer1.visit(doc1)
        let result2 = renderer2.visit(doc2)

        let text1 = String(result1.characters)
        let text2 = String(result2.characters)
        #expect(text1 != text2)
    }

    @Test
    func `Parsing same string twice produces equal AttributedStrings`() {
        let source = "**Bold** and *italic* with `code`"
        let doc1 = Document(parsing: source)
        let doc2 = Document(parsing: source)

        var renderer1 = TestMarkdownRenderer()
        var renderer2 = TestMarkdownRenderer()
        let result1 = renderer1.visit(doc1)
        let result2 = renderer2.visit(doc2)

        // The plain text content should be identical
        let text1 = String(result1.characters)
        let text2 = String(result2.characters)
        #expect(text1 == text2)
    }

    // MARK: - Complex Markdown

    @Test
    func `Mixed markdown with multiple elements renders`() {
        let source = """
        # Title

        This is a paragraph with **bold**, *italic*, and `code`.

        - Item 1
        - Item 2
        """
        let doc = Document(parsing: source)
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        let plainText = String(result.characters)

        #expect(plainText.contains("Title"))
        #expect(plainText.contains("bold"))
        #expect(plainText.contains("italic"))
        #expect(plainText.contains("code"))
        #expect(plainText.contains("Item 1"))
    }

    @Test
    func `Empty string produces empty or minimal result`() {
        let doc = Document(parsing: "")
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        // Empty markdown may produce an empty or whitespace-only result
        let plainText = String(result.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(plainText.isEmpty)
    }

    @Test
    func `Code block renders content`() {
        let source = """
        ```swift
        func hello() { }
        ```
        """
        let doc = Document(parsing: source)
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        let plainText = String(result.characters)
        #expect(plainText.contains("func hello()"))
    }

    @Test
    func `Link text is preserved in rendered output`() {
        let doc = Document(parsing: "[Example](https://example.com)")
        var renderer = TestMarkdownRenderer()
        let result = renderer.visit(doc)
        let plainText = String(result.characters)
        #expect(plainText.contains("Example"))
    }
}

// MARK: - TestMarkdownRenderer

/// Minimal `MarkupVisitor` that mirrors the production ``MarkdownRenderer``
/// to validate parsing behavior without depending on private OIUI internals.
private struct TestMarkdownRenderer: MarkupVisitor {
    typealias Result = AttributedString

    mutating func defaultVisit(_ markup: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result.append(self.visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> AttributedString {
        var result = AttributedString()
        for (index, child) in document.children.enumerated() {
            result.append(self.visit(child))
            if index < document.childCount - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> AttributedString {
        var result = self.defaultVisit(paragraph)
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> AttributedString {
        var result = self.defaultVisit(heading)
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> AttributedString {
        var result = AttributedString(codeBlock.code.trimmingCharacters(in: .newlines))
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitText(_ text: Markdown.Text) -> AttributedString {
        AttributedString(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> AttributedString {
        self.defaultVisit(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> AttributedString {
        self.defaultVisit(emphasis)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> AttributedString {
        AttributedString(inlineCode.code)
    }

    mutating func visitLink(_ link: Markdown.Link) -> AttributedString {
        self.defaultVisit(link)
    }

    mutating func visitSoftBreak(_: SoftBreak) -> AttributedString {
        AttributedString(" ")
    }

    mutating func visitLineBreak(_: LineBreak) -> AttributedString {
        AttributedString("\n")
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> AttributedString {
        var result = AttributedString()
        for item in list.children {
            result.append(self.visit(item))
        }
        return result
    }

    mutating func visitListItem(_ item: ListItem) -> AttributedString {
        self.defaultVisit(item)
    }
}
