import SwiftUI

// MARK: - Custom Agent UI

extension ReviewPromptSheet {
    func customAgentRow(
        _ agent: CustomReviewAgent, index: Int
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: agent.icon)
                .foregroundStyle(
                    agent.isEnabled ? agent.iconColor : .secondary
                )
                .frame(width: 18)

            Text(agent.name.isEmpty ? "Unnamed" : agent.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(
                    agent.isEnabled ? .primary : .secondary
                )

            Spacer()

            Button {
                editingCustomAgent = agent
                showAddAgent = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Toggle("", isOn: Binding(
                get: { customAgents[safe: index]?.isEnabled ?? true },
                set: { newValue in
                    if customAgents.indices.contains(index) {
                        customAgents[index].isEnabled = newValue
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            Button {
                customAgents.removeAll { $0.id == agent.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .opacity(agent.isEnabled ? 0.5 : 0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func customAgentForm(
        _ agent: CustomReviewAgent
    ) -> some View {
        let isEditing = customAgents.contains { $0.id == agent.id }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isEditing ? "Edit Agent" : "New Agent")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            agentNameField
            agentIconPicker
            agentColorPicker
            agentPromptField
            agentFormActions(isEditing: isEditing)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.blue.opacity(0.3), lineWidth: 1)
        )
    }

    private var agentNameField: some View {
        TextField("Agent name", text: Binding(
            get: { editingCustomAgent?.name ?? "" },
            set: { editingCustomAgent?.name = $0 }
        ))
        .textFieldStyle(.roundedBorder)
    }

    private var agentIconPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Icon")
                .font(.caption.bold())

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(32), spacing: 4),
                    count: 13
                ),
                spacing: 4
            ) {
                ForEach(
                    CustomReviewAgent.availableIcons, id: \.self
                ) { icon in
                    iconButton(icon)
                }
            }
        }
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = editingCustomAgent?.icon == icon
        let color = editingCustomAgent?.iconColor ?? .blue
        return Button {
            editingCustomAgent?.icon = icon
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(
                    isSelected ? color.opacity(0.2) : .clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? color : .clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? color : .secondary)
    }

    private var agentColorPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Color")
                .font(.caption.bold())

            HStack(spacing: 6) {
                ForEach(
                    CustomReviewAgent.availableColors, id: \.name
                ) { item in
                    colorButton(item)
                }
            }
        }
    }

    private func colorButton(
        _ item: (name: String, color: Color)
    ) -> some View {
        let isSelected = editingCustomAgent?.colorName == item.name
        return Button {
            editingCustomAgent?.colorName = item.name
        } label: {
            Circle()
                .fill(item.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(
                            .white, lineWidth: isSelected ? 2 : 0
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            item.color,
                            lineWidth: isSelected ? 1 : 0
                        )
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
    }

    private var agentPromptField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt")
                .font(.caption.bold())

            promptEditor(
                text: Binding(
                    get: { editingCustomAgent?.prompt ?? "" },
                    set: { editingCustomAgent?.prompt = $0 }
                ),
                placeholder: "Describe what this agent should review..."
            )
            .frame(height: 100)
        }
    }

    private func agentFormActions(
        isEditing: Bool
    ) -> some View {
        HStack {
            Spacer()

            Button("Cancel") {
                showAddAgent = false
                editingCustomAgent = nil
            }
            .controlSize(.small)

            Button(isEditing ? "Update" : "Add") {
                guard let agent = editingCustomAgent,
                      !agent.name.isEmpty,
                      !agent.prompt.isEmpty else { return }

                if let idx = customAgents.firstIndex(
                    where: { $0.id == agent.id }
                ) {
                    customAgents[idx] = agent
                } else {
                    customAgents.append(agent)
                }
                showAddAgent = false
                editingCustomAgent = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
                editingCustomAgent?.name.isEmpty ?? true
                    || editingCustomAgent?.prompt.isEmpty ?? true
            )
        }
    }
}
