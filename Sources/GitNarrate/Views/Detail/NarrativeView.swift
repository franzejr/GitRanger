import AppKit
import SwiftUI

struct NarrativeView: View {
    @Bindable var viewModel: NarrativeViewModel
    @State private var diagramCopied = false
    @State private var diagramZoom: CGFloat = 1.0
    @State private var diagramHeight: CGFloat = 300
    @State private var dragStartHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commit Narrative")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let timespan = viewModel.timespan {
                        timespanLabel(timespan)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isLoading {
                        loadingState
                    } else if let error = viewModel.error {
                        errorState(error)
                    } else if let narrative = viewModel.narrative {
                        narrativeContent(narrative)
                        diagramSection
                    }
                }
                .padding()
            }
        }
    }

    private func timespanLabel(
        _ timespan: (from: Date, to: Date)
    ) -> Text {
        Text("\(viewModel.commitCount) commits \u{2022} ") +
        Text(timespan.from, style: .date) +
        Text(" \u{2013} ") +
        Text(timespan.to, style: .date)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Crafting the story...")
                .foregroundStyle(.secondary)
            Text("This may take a moment for \(viewModel.commitCount) commits.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Failed to generate narrative")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func narrativeContent(_ narrative: String) -> some View {
        let lines = narrative.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                bulletRow(String(trimmed.dropFirst(2)))
            } else {
                Text(trimmed)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.bottom, 4)
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .frame(width: 5, height: 5)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    // MARK: - Diagram

    @ViewBuilder
    private var diagramSection: some View {
        Divider()
            .padding(.vertical, 4)

        if let diagram = viewModel.mermaidDiagram, !diagram.isEmpty {
            diagramContent(diagram)
        } else if viewModel.isLoadingDiagram {
            diagramLoading
        } else if let err = viewModel.diagramError {
            diagramError(err)
        } else {
            generateDiagramButton
        }
    }

    private var generateDiagramButton: some View {
        HStack {
            Spacer()
            Button {
                Task { await viewModel.generateDiagram() }
            } label: {
                Label("Generate Diagram", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var diagramLoading: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Generating diagram...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func diagramError(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await viewModel.generateDiagram() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func diagramContent(_ diagram: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Change Flow", systemImage: "arrow.triangle.branch")
                    .font(.headline)

                Spacer()

                zoomControls

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagram, forType: .string)
                    diagramCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        diagramCopied = false
                    }
                } label: {
                    Label(
                        diagramCopied ? "Copied" : "Copy Mermaid",
                        systemImage: diagramCopied
                            ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            GroupBox {
                MermaidWebView(mermaidCode: diagram, zoom: diagramZoom)
                    .frame(height: diagramHeight)
            }

            diagramResizeHandle
        }
    }

    private var diagramResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(width: 36, height: 4)
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newHeight = dragStartHeight
                            + value.translation.height
                        diagramHeight = min(max(newHeight, 150), 800)
                    }
                    .onEnded { _ in
                        dragStartHeight = diagramHeight
                    }
            )
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                diagramZoom = max(0.5, diagramZoom - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(diagramZoom <= 0.5)

            Text("\(Int(diagramZoom * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40)

            Button {
                diagramZoom = min(3.0, diagramZoom + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(diagramZoom >= 3.0)
        }
    }
}
