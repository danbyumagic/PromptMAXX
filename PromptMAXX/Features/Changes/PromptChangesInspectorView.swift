import SwiftUI

/// A local, factual inspector for the text currently in the editor.
public struct PromptChangesInspectorView: View {
    private enum ViewMode: String, CaseIterable {
        case inline
        case split

        var title: String {
            switch self {
            case .inline: return "Inline"
            case .split: return "Split"
            }
        }
    }

    private enum Column {
        case original
        case refined
    }

    public let originalText: String
    public let refinedText: String
    public let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewMode: ViewMode = .inline
    @State private var didCopy = false

    private let diff: PromptDiff

    public init(
        originalText: String,
        refinedText: String,
        onCopy: @escaping (String) -> Void = { _ in }
    ) {
        self.originalText = originalText
        self.refinedText = refinedText
        self.onCopy = onCopy
        diff = PromptDiff(original: originalText, refined: refinedText)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summaryBar
            Divider()
            diffSurface
            footer
        }
        .frame(minWidth: 780, idealWidth: 920, minHeight: 560, idealHeight: 700)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 38, height: 38)
                .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Prompt Changes")
                    .font(.title2.weight(.semibold))
                Text("A line-by-line view of your source and refined prompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            changeMetric(
                value: diff.addedLineCount,
                label: "added",
                color: .green,
                systemImage: "plus"
            )
            changeMetric(
                value: diff.removedLineCount,
                label: "removed",
                color: .red,
                systemImage: "minus"
            )
            changeMetric(
                value: diff.unchangedLineCount,
                label: "unchanged",
                color: .secondary,
                systemImage: "equal"
            )

            Spacer(minLength: 16)

            Picker("Diff view", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 158)
            .accessibilityLabel("Diff view")

            Button {
                onCopy(refinedText)
                didCopy = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "Copied" : "Copy refined", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .tint(didCopy ? .green : nil)
            .disabled(refinedText.isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(.bar)
    }

    private func changeMetric(
        value: Int,
        label: String,
        color: Color,
        systemImage: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) lines \(label)")
    }

    @ViewBuilder
    private var diffSurface: some View {
        if diff.hasChanges {
            VStack(spacing: 0) {
                diffHeader
                ScrollView {
                    if viewMode == .inline {
                        inlineRows
                    } else {
                        splitRows
                    }
                }
                .scrollIndicators(.visible)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        } else {
            noChangesState
        }
    }

    private var diffHeader: some View {
        HStack(spacing: 0) {
            Text(viewMode == .inline ? "CHANGE" : "ORIGINAL")
                .frame(width: viewMode == .inline ? 92 : nil, alignment: .leading)
            if viewMode == .split {
                Spacer()
                Text("REFINED")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Text("LINES")
                .frame(width: 74, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.tertiary)
        .tracking(0.8)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quinary, in: UnevenRoundedRectangle(cornerRadii: .init(topLeading: 10, topTrailing: 10)))
    }

    private var inlineRows: some View {
        VStack(spacing: 0) {
            ForEach(diff.lines) { line in
                inlineRow(line)
            }
        }
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 10, bottomTrailing: 10)))
        .overlay {
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 10, bottomTrailing: 10))
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func inlineRow(_ line: PromptDiff.Line) -> some View {
        HStack(spacing: 0) {
            Text(marker(for: line.kind))
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundStyle(markerColor(for: line.kind))
                .frame(width: 28)

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(line.kind == .unchanged ? .primary : markerColor(for: line.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Text(lineNumberLabel(for: line))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground(for: line.kind))
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var splitRows: some View {
        VStack(spacing: 0) {
            ForEach(diff.lines) { line in
                HStack(spacing: 0) {
                    splitCell(line, column: .original)
                    Divider()
                    splitCell(line, column: .refined)
                }
                .overlay(alignment: .bottom) { Divider().opacity(0.45) }
            }
        }
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 10, bottomTrailing: 10)))
        .overlay {
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 10, bottomTrailing: 10))
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func splitCell(_ line: PromptDiff.Line, column: Column) -> some View {
        let text: String?
        let lineNumber: Int?
        let kind: PromptDiff.LineKind?

        switch column {
        case .original:
            text = line.originalLineNumber == nil ? nil : line.text
            lineNumber = line.originalLineNumber
            kind = line.kind == .added ? nil : line.kind
        case .refined:
            text = line.refinedLineNumber == nil ? nil : line.text
            lineNumber = line.refinedLineNumber
            kind = line.kind == .removed ? nil : line.kind
        }

        return HStack(spacing: 8) {
            Text(lineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)
            Text(text ?? " ")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(kind.map(markerColor(for:)) ?? Color.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.map(rowBackground(for:)) ?? Color.clear)
    }

    private var noChangesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.green)
            Text("No line-level changes")
                .font(.headline)
            Text("The source and refined prompt are identical.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            legend(color: .green, label: "Added")
            legend(color: .red, label: "Removed")
            legend(color: .secondary, label: "Unchanged")
            Spacer()
            Text("Local comparison · no prompt data leaves this Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func marker(for kind: PromptDiff.LineKind) -> String {
        switch kind {
        case .unchanged: return "·"
        case .added: return "+"
        case .removed: return "−"
        }
    }

    private func markerColor(for kind: PromptDiff.LineKind) -> Color {
        switch kind {
        case .unchanged: return .secondary
        case .added: return .green
        case .removed: return .red
        }
    }

    private func rowBackground(for kind: PromptDiff.LineKind) -> Color {
        switch kind {
        case .unchanged: return .clear
        case .added: return .green.opacity(0.10)
        case .removed: return .red.opacity(0.10)
        }
    }

    private func lineNumberLabel(for line: PromptDiff.Line) -> String {
        switch (line.originalLineNumber, line.refinedLineNumber) {
        case let (original?, refined?): return "\(original) → \(refined)"
        case let (original?, nil): return "\(original) ·"
        case let (nil, refined?): return "· \(refined)"
        case (nil, nil): return ""
        }
    }
}

#Preview {
    PromptChangesInspectorView(
        originalText: "Summarize the customer issue.\nKeep the tone friendly.\nMention the next step.",
        refinedText: "Summarize the customer issue in two sentences.\nKeep the tone warm and direct.\nEnd with the next step."
    )
}
