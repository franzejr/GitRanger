import SwiftUI

struct ImpactBadge: View {
    let level: ImpactLevel

    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch level {
        case .patch: .gray
        case .minor: .blue
        case .major: .orange
        case .breaking: .red
        }
    }
}
