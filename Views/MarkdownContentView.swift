import SwiftUI

struct MarkdownContentView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .paragraph(let spans):
            spanText(spans)
                .foregroundStyle(.white.opacity(0.8))
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, spans in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.system(size: 14))
                        spanText(spans)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, spans in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                        spanText(spans)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        case .codeBlock(_, let code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.06))
                )
        case .divider:
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.vertical, 2)
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        let size: CGFloat
        let weight: Font.Weight
        switch level {
        case 1:
            size = 18; weight = .bold
        case 2:
            size = 16; weight = .semibold
        default:
            size = 15; weight = .medium
        }
        return Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(0.9))
    }

    private func spanText(_ spans: [MarkdownSpan]) -> Text {
        spans.reduce(Text("")) { result, span in
            switch span {
            case .text(let str):
                return result + Text(str)
                    .font(.system(size: 15))
            case .bold(let str):
                return result + Text(str)
                    .font(.system(size: 15, weight: .semibold))
            case .italic(let str):
                return result + Text(str)
                    .font(.system(size: 15))
                    .italic()
            case .code(let str):
                return result + Text(str)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}
