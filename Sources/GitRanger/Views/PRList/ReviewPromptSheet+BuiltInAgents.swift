import SwiftUI

// MARK: - Built-in Agent Prompt Sections

extension ReviewPromptSheet {
    @ViewBuilder
    func agentPromptSection(
        _ agent: ReviewAgent
    ) -> some View {
        let binding = Binding<String>(
            get: { agentPromptTexts[agent] ?? "" },
            set: { agentPromptTexts[agent] = $0 }
        )
        let hasCustom = !binding.wrappedValue.isEmpty
        let isEnabled = agentEnabled[agent] ?? true
        let enabledBinding = Binding<Bool>(
            get: { agentEnabled[agent] ?? true },
            set: { agentEnabled[agent] = $0 }
        )

        DisclosureGroup {
            agentPromptContent(
                agent, binding: binding,
                hasCustom: hasCustom, isEnabled: isEnabled
            )
        } label: {
            agentPromptLabel(
                agent, hasCustom: hasCustom,
                isEnabled: isEnabled,
                enabledBinding: enabledBinding
            )
        }
        .padding(8)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .opacity(isEnabled ? 0.5 : 0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func agentPromptContent(
        _ agent: ReviewAgent,
        binding: Binding<String>,
        hasCustom: Bool,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            promptEditor(
                text: binding,
                placeholder: "Custom instructions for \(agent.displayName)..."
            )
            .frame(height: 80)

            if !hasCustom {
                usingDefaultHint("Using default prompt.")
            }

            HStack(spacing: 8) {
                Button("Load Default") {
                    agentPromptTexts[agent] = PromptBuilder.agentPrompt(
                        for: agent
                    )
                }
                .controlSize(.small)

                if hasCustom {
                    Button("Clear") {
                        agentPromptTexts[agent] = ""
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.top, 4)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }

    private func agentPromptLabel(
        _ agent: ReviewAgent,
        hasCustom: Bool,
        isEnabled: Bool,
        enabledBinding: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: agent.icon)
                .foregroundStyle(
                    isEnabled ? agent.iconColor : .secondary
                )
                .frame(width: 18)

            Text(agent.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isEnabled ? .primary : .secondary)

            Text(agent.shortDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            if hasCustom && isEnabled {
                Text("Custom")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    func usingDefaultHint(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }
}
