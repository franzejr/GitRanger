import SwiftUI

struct DiffView: View {
    let diff: String

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(line.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 0.5)
                        .background(line.backgroundColor)
                }
            }
        }
    }

    private var lines: [DiffLine] {
        diff.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                DiffLine(text: line, color: .secondary, backgroundColor: .clear)
            } else if line.hasPrefix("+") {
                DiffLine(text: line, color: .green, backgroundColor: Color.green.opacity(0.05))
            } else if line.hasPrefix("-") {
                DiffLine(text: line, color: .red, backgroundColor: Color.red.opacity(0.05))
            } else if line.hasPrefix("@@") {
                DiffLine(text: line, color: .blue, backgroundColor: Color.blue.opacity(0.05))
            } else {
                DiffLine(text: line, color: .secondary, backgroundColor: .clear)
            }
        }
    }
}

private struct DiffLine {
    let text: String
    let color: Color
    let backgroundColor: Color
}
