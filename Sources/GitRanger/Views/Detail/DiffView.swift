import SwiftUI

struct DiffView: View {
    let diff: String
    @Environment(\.colorScheme) private var colorScheme

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
        let theme = colorScheme == .dark ? DiffColors.dark : DiffColors.light

        return diff.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                DiffLine(text: line, color: .secondary, backgroundColor: .clear)
            } else if line.hasPrefix("+") {
                DiffLine(text: line, color: theme.additionText, backgroundColor: theme.additionBg)
            } else if line.hasPrefix("-") {
                DiffLine(text: line, color: theme.deletionText, backgroundColor: theme.deletionBg)
            } else if line.hasPrefix("@@") {
                DiffLine(text: line, color: theme.hunkText, backgroundColor: theme.hunkBg)
            } else {
                DiffLine(text: line, color: .secondary, backgroundColor: .clear)
            }
        }
    }
}

// MARK: - GitHub-style diff color themes

private struct DiffColorTheme {
    let additionText: Color
    let additionBg: Color
    let deletionText: Color
    let deletionBg: Color
    let hunkText: Color
    let hunkBg: Color
}

private enum DiffColors {
    // GitHub light theme colors
    static let light = DiffColorTheme(
        additionText: Color(red: 0.14, green: 0.28, blue: 0.17),  // dark green text
        additionBg: Color(red: 0.90, green: 1.0, blue: 0.93),     // #E6FFEC
        deletionText: Color(red: 0.51, green: 0.13, blue: 0.12),  // dark red text
        deletionBg: Color(red: 1.0, green: 0.92, blue: 0.91),     // #FFEBE9
        hunkText: Color(red: 0.13, green: 0.33, blue: 0.53),      // dark blue text
        hunkBg: Color(red: 0.87, green: 0.96, blue: 1.0)          // #DDF4FF
    )

    // GitHub dark theme colors
    static let dark = DiffColorTheme(
        additionText: Color(red: 0.56, green: 0.94, blue: 0.56),  // light green text
        additionBg: Color(red: 0.10, green: 0.27, blue: 0.13),    // #19441F
        deletionText: Color(red: 1.0, green: 0.55, blue: 0.55),   // light red text
        deletionBg: Color(red: 0.29, green: 0.15, blue: 0.12),    // #49261E
        hunkText: Color(red: 0.53, green: 0.75, blue: 0.98),      // light blue text
        hunkBg: Color(red: 0.12, green: 0.18, blue: 0.29)         // #1E2E4A
    )
}

private struct DiffLine {
    let text: String
    let color: Color
    let backgroundColor: Color
}
