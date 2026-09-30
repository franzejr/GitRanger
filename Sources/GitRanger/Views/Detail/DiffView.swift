import SwiftUI

enum DiffPresentation {
    case inline
    case split
}

struct DiffView: View {
    let diff: String
    var presentation: DiffPresentation = .inline
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if presentation == .split,
                       line.kind != .hunk,
                       line.kind != .metadata {
                        splitRow(line)
                    } else {
                        inlineRow(line)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(GRTheme.code(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(GRTheme.line(colorScheme), lineWidth: 1)
        }
        .textSelection(.enabled)
    }

    private var lines: [DiffLine] {
        DiffParser.parse(diff)
    }

    private func inlineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.inlineNumber ?? "")
                .foregroundStyle(GRTheme.muted(colorScheme).opacity(0.65))
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 10)

            Text(line.sign)
                .frame(width: 14, alignment: .leading)

            Text(line.text)
                .frame(minWidth: presentation == .split ? 1_000 : 620, alignment: .leading)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(foreground(for: line.kind))
        .frame(minHeight: 18)
        .background(background(for: line.kind))
    }

    private func splitRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            splitCell(line, side: .old)
            Rectangle()
                .fill(GRTheme.line(colorScheme))
                .frame(width: 1)
            splitCell(line, side: .new)
        }
        .frame(minHeight: 18)
    }

    private func splitCell(_ line: DiffLine, side: DiffSide) -> some View {
        let visible = line.isVisible(on: side)
        return HStack(spacing: 0) {
            Text(visible ? line.number(for: side) ?? "" : "")
                .foregroundStyle(GRTheme.muted(colorScheme).opacity(0.65))
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 10)

            Text(visible ? line.sign : "")
                .frame(width: 14, alignment: .leading)

            Text(visible ? line.text : "")
                .frame(minWidth: 430, alignment: .leading)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(foreground(for: line.kind))
        .background(visible ? background(for: line.kind) : .clear)
    }

    private func foreground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .hunk: GRTheme.link(colorScheme)
        case .addition, .deletion, .context:
            if colorScheme == .dark {
                Color(red: 0.812, green: 0.820, blue: 0.847)
            } else {
                Color(red: 0.165, green: 0.169, blue: 0.192)
            }
        case .metadata: GRTheme.muted(colorScheme)
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition:
            GRTheme.success.opacity(colorScheme == .dark ? 0.13 : 0.18)
        case .deletion:
            GRTheme.danger.opacity(colorScheme == .dark ? 0.15 : 0.18)
        case .hunk:
            GRTheme.link(colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.10)
        case .context, .metadata:
            .clear
        }
    }
}

private enum DiffSide {
    case old
    case new
}

private struct DiffLine {
    enum Kind {
        case addition
        case deletion
        case hunk
        case context
        case metadata
    }

    let oldNumber: String?
    let newNumber: String?
    let sign: String
    let text: String
    let kind: Kind

    var inlineNumber: String? {
        kind == .deletion ? oldNumber : newNumber
    }

    func number(for side: DiffSide) -> String? {
        switch side {
        case .old: oldNumber
        case .new: newNumber
        }
    }

    func isVisible(on side: DiffSide) -> Bool {
        switch kind {
        case .addition:
            side == .new
        case .deletion:
            side == .old
        case .context:
            true
        case .hunk, .metadata:
            false
        }
    }
}

private enum DiffParser {
    static func parse(_ diff: String) -> [DiffLine] {
        var oldLine: Int?
        var newLine: Int?

        return diff.components(separatedBy: "\n").map { raw in
            parseLine(raw, oldLine: &oldLine, newLine: &newLine)
        }
    }

    private static func parseLine(
        _ raw: String,
        oldLine: inout Int?,
        newLine: inout Int?
    ) -> DiffLine {
        if raw.hasPrefix("@@") {
            let starts = hunkStarts(raw)
            oldLine = starts.old
            newLine = starts.new
            return line(raw, kind: .hunk)
        }
        if raw.hasPrefix("+") && !raw.hasPrefix("+++") {
            return addition(raw, newLine: &newLine)
        }
        if raw.hasPrefix("-") && !raw.hasPrefix("---") {
            return deletion(raw, oldLine: &oldLine)
        }
        if raw.hasPrefix(" ") {
            return context(raw, oldLine: &oldLine, newLine: &newLine)
        }
        return line(raw, kind: .metadata)
    }

    private static func addition(_ raw: String, newLine: inout Int?) -> DiffLine {
        let number = newLine.map(String.init)
        newLine = newLine.map { $0 + 1 }
        return line(String(raw.dropFirst()), newNumber: number, sign: "+", kind: .addition)
    }

    private static func deletion(_ raw: String, oldLine: inout Int?) -> DiffLine {
        let number = oldLine.map(String.init)
        oldLine = oldLine.map { $0 + 1 }
        return line(String(raw.dropFirst()), oldNumber: number, sign: "−", kind: .deletion)
    }

    private static func context(
        _ raw: String,
        oldLine: inout Int?,
        newLine: inout Int?
    ) -> DiffLine {
        let line = line(
            String(raw.dropFirst()),
            oldNumber: oldLine.map(String.init),
            newNumber: newLine.map(String.init),
            kind: .context
        )
        oldLine = oldLine.map { $0 + 1 }
        newLine = newLine.map { $0 + 1 }
        return line
    }

    private static func line(
        _ text: String,
        oldNumber: String? = nil,
        newNumber: String? = nil,
        sign: String = "",
        kind: DiffLine.Kind
    ) -> DiffLine {
        DiffLine(
            oldNumber: oldNumber,
            newNumber: newNumber,
            sign: sign,
            text: text,
            kind: kind
        )
    }

    private static func hunkStarts(_ line: String) -> (old: Int?, new: Int?) {
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return (nil, nil) }
        return (
            parseStart(parts[1].dropFirst()),
            parseStart(parts[2].dropFirst())
        )
    }

    private static func parseStart(_ token: Substring) -> Int? {
        Int(token.split(separator: ",").first ?? token)
    }
}
