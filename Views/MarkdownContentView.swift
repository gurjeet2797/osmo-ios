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
        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        case .mathBlock(let expr):
            Text(expr)
                .font(.system(size: 15, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .italic()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.04))
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
        case .divider:
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.vertical, 2)
        }
    }

    private func tableView(headers: [String], rows: [MarkdownTableRow]) -> some View {
        let colCount = max(headers.count, rows.first?.cells.count ?? 0)

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { col in
                        Text(col < headers.count ? headers[col] : "")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .frame(minWidth: 60, maxWidth: 180, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                }
                .background(Color.white.opacity(0.08))

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(0..<colCount, id: \.self) { col in
                            Text(col < row.cells.count ? row.cells[col] : "")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(3)
                                .frame(minWidth: 60, maxWidth: 180, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(rowIdx % 2 == 0 ? Color.white.opacity(0.03) : Color.clear)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
            case .math(let str):
                return result + Text(str)
                    .font(.system(size: 15, weight: .light, design: .serif))
                    .foregroundColor(.white.opacity(0.85))
                    .italic()
            }
        }
    }
}
