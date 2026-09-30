import SwiftUI

enum GRTheme {
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.239)
    static let onAccent = Color(red: 0.102, green: 0.051, blue: 0.031)
    static let success = Color(red: 0.239, green: 0.863, blue: 0.592)
    static let warning = Color(red: 0.961, green: 0.647, blue: 0.141)
    static let danger = Color(red: 1.0, green: 0.420, blue: 0.420)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.106, green: 0.110, blue: 0.125)
            : Color(red: 0.965, green: 0.965, blue: 0.969)
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.082, green: 0.086, blue: 0.098)
            : Color(red: 0.925, green: 0.925, blue: 0.933)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.125, green: 0.129, blue: 0.149)
            : .white
    }

    static func code(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.078, green: 0.082, blue: 0.098)
            : .white
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.169, green: 0.173, blue: 0.200)
            : Color(red: 0.863, green: 0.863, blue: 0.878)
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.498, green: 0.506, blue: 0.549)
            : Color(red: 0.478, green: 0.486, blue: 0.525)
    }

    static func mutedSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.663, green: 0.671, blue: 0.710)
            : Color(red: 0.361, green: 0.369, blue: 0.408)
    }

    static func segment(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.165, green: 0.169, blue: 0.196)
            : Color(red: 0.886, green: 0.886, blue: 0.902)
    }

    static func segmentSelected(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.227, green: 0.231, blue: 0.267)
            : .white
    }

    static func selection(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.165, green: 0.169, blue: 0.196)
            : Color(red: 0.902, green: 0.902, blue: 0.918)
    }

    static func accentSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.227, green: 0.133, blue: 0.098)
            : Color(red: 1.0, green: 0.902, blue: 0.863)
    }

    static func link(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.498, green: 0.698, blue: 1.0)
            : Color(red: 0.184, green: 0.435, blue: 0.839)
    }
}

struct GRMonogram: View {
    var size: CGFloat = 26

    var body: some View {
        Text("GR")
            .font(.system(size: size * 0.38, weight: .bold, design: .monospaced))
            .tracking(-1)
            .foregroundStyle(GRTheme.onAccent)
            .frame(width: size, height: size)
            .background(GRTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
    }
}

struct GRSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct GRCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 10
    var border: Color?

    func body(content: Content) -> some View {
        content
            .background(GRTheme.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(border ?? GRTheme.line(colorScheme), lineWidth: 1)
            }
    }
}

extension View {
    func grCard(radius: CGFloat = 10, border: Color? = nil) -> some View {
        modifier(GRCardModifier(radius: radius, border: border))
    }
}
