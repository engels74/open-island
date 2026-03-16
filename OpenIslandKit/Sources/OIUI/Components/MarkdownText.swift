import Markdown
package import SwiftUI
import Synchronization

// MARK: - MarkdownText

/// A SwiftUI view that parses a Markdown string and renders it as styled `Text`.
///
/// Internally uses Apple's `swift-markdown` library to parse the source into a
/// `Markup` AST, then walks the tree with ``MarkdownRenderer`` to produce an
/// `AttributedString`. Parsed documents are cached by source string to avoid
/// redundant work when the same text is rendered across frames.
package struct MarkdownText: View {
    // MARK: Lifecycle

    package init(_ source: String) {
        self.source = source
    }

    // MARK: Package

    package var body: some View {
        self.renderedContent
    }

    // MARK: Private

    private let source: String

    private var renderedContent: some View {
        let attributed = DocumentCache.shared.attributedString(for: self.source)
        return Text(attributed)
            .textSelection(.enabled)
    }
}

// MARK: - DocumentCache

/// Thread-safe cache mapping Markdown source text to rendered `AttributedString`.
///
/// Uses `Mutex` from the `Synchronization` framework for safe concurrent access
/// without `@unchecked Sendable`.
private final class DocumentCache: Sendable {
    // MARK: Internal

    static let shared = DocumentCache()

    func attributedString(for source: String) -> AttributedString {
        if let cached = self.storage.withLock({ $0[source] }) {
            return cached
        }
        let document = Document(parsing: source)
        var renderer = MarkdownRenderer()
        let result = renderer.visit(document)
        self.storage.withLock { $0[source] = result }
        return result
    }

    // MARK: Private

    private let storage = Mutex<[String: AttributedString]>([:])
}

// MARK: - MarkdownRenderer

/// A `MarkupVisitor` that converts a `swift-markdown` AST into `AttributedString`.
///
/// Walks each node, accumulating styled attributed string fragments. Block
/// elements append trailing newlines; inline elements apply character-level
/// attributes (bold, italic, monospace, links, strikethrough).
private struct MarkdownRenderer: MarkupVisitor {
    typealias Result = AttributedString

    // MARK: - Document

    mutating func defaultVisit(_ markup: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result.append(self.visit(child))
        }
        return result
    }

    // MARK: - Block Elements

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
        let font: Font = switch heading.level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        case 4: .headline
        case 5: .subheadline.bold()
        default: .subheadline
        }
        result.font = font
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> AttributedString {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        var result = AttributedString(code)
        result.font = .system(.body, design: .monospaced)
        result.backgroundColor = Color(.sRGB, white: 0.15, opacity: 1.0)
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> AttributedString {
        var result = AttributedString("\u{258E} ")
        result.foregroundColor = .secondary
        var content = self.defaultVisit(blockQuote)
        content.foregroundColor = .secondary
        result.append(content)
        return result
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> AttributedString {
        var result = AttributedString()
        for (index, item) in orderedList.children.enumerated() {
            var prefix = AttributedString("\(index + 1). ")
            prefix.font = .body
            result.append(prefix)
            result.append(self.visit(item))
        }
        return result
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> AttributedString {
        var result = AttributedString()
        for item in unorderedList.children {
            var prefix = AttributedString("  \u{2022} ")
            prefix.font = .body
            result.append(prefix)
            result.append(self.visit(item))
        }
        return result
    }

    mutating func visitListItem(_ listItem: ListItem) -> AttributedString {
        self.defaultVisit(listItem)
    }

    mutating func visitThematicBreak(_: ThematicBreak) -> AttributedString {
        var divider = AttributedString("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n")
        divider.foregroundColor = .secondary
        return divider
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> AttributedString {
        AttributedString(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> AttributedString {
        var result = self.defaultVisit(strong)
        result.font = .body.bold()
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> AttributedString {
        var result = self.defaultVisit(emphasis)
        result.font = .body.italic()
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> AttributedString {
        var result = AttributedString(inlineCode.code)
        result.font = .system(.body, design: .monospaced)
        result.backgroundColor = Color(.sRGB, white: 0.2, opacity: 1.0)
        return result
    }

    mutating func visitLink(_ link: Markdown.Link) -> AttributedString {
        var result = self.defaultVisit(link)
        if let destination = link.destination, let url = URL(string: destination) {
            result.link = url
            result.foregroundColor = .blue
        }
        return result
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> AttributedString {
        var result = self.defaultVisit(strikethrough)
        result.strikethroughStyle = .single
        return result
    }

    mutating func visitSoftBreak(_: SoftBreak) -> AttributedString {
        AttributedString(" ")
    }

    mutating func visitLineBreak(_: LineBreak) -> AttributedString {
        AttributedString("\n")
    }

    mutating func visitImage(_ image: Markdown.Image) -> AttributedString {
        let alt = image.plainText
        var result = AttributedString(alt.isEmpty ? "[image]" : "[\(alt)]")
        result.foregroundColor = .secondary
        result.font = .body.italic()
        return result
    }
}

// MARK: - Previews

private let sampleMarkdown = """
# Heading 1

## Heading 2

### Heading 3

This is a paragraph with **bold**, *italic*, `inline code`, \
~~strikethrough~~, and a [link](https://example.com).

> This is a block quote with some quoted text
> spanning multiple lines.

---

```swift
func greet(_ name: String) -> String {
    "Hello, \\(name)!"
}
```

Ordered list:

1. First item
2. Second item
3. Third item

Unordered list:

- Apple
- Banana
- Cherry
"""

#Preview("MarkdownText — All Elements") {
    ScrollView {
        MarkdownText(sampleMarkdown)
            .padding()
    }
    .frame(width: 480, height: 600)
    .background(.black)
    .foregroundStyle(.white)
}

#Preview("MarkdownText — Short") {
    MarkdownText("Hello **world** in `code`")
        .padding()
        .background(.black)
        .foregroundStyle(.white)
}
