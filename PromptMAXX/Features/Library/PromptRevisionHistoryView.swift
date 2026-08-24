import SwiftUI

struct PromptRevisionHistoryView: View {
    let document: PromptDocument
    let onCopy: (String) -> Void
    let onRestore: (PromptDocument.ID, PromptRevision) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRevisionID: UUID?

    private var selectedRevision: PromptRevision? {
        document.revisions.first(where: { $0.id == selectedRevisionID }) ?? document.latestRevision
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Revision History")
                        .font(.title2.weight(.semibold))
                    Text(document.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()

            HSplitView {
                List(selection: $selectedRevisionID) {
                    ForEach(document.revisions.reversed()) { revision in
                        RevisionRow(revision: revision, isLatest: revision.id == document.latestRevision?.id)
                            .tag(revision.id)
                            .contentShape(Rectangle())
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 240, idealWidth: 280)

                if let revision = selectedRevision {
                    revisionDetail(revision)
                        .frame(minWidth: 420, maxWidth: .infinity)
                } else {
                    ContentUnavailableView("No Revisions", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .onAppear {
            selectedRevisionID = document.latestRevision?.id
        }
    }

    private func revisionDetail(_ revision: PromptRevision) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(revision.name)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        onRestore(document.id, revision)
                        dismiss()
                    } label: {
                        Label("Restore as New Revision", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Load this revision into the editor; Save will append a new revision")
                }

                Text(revision.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                metadata(revision)

                if !revision.changeSummary.isEmpty {
                    labeledText("Change Summary", revision.changeSummary)
                }

                labeledCopyableText("Source", revision.sourceText)
                if let compiled = revision.compiledText, !compiled.isEmpty {
                    labeledCopyableText("Compiled", compiled)
                }
                if let spec = revision.spec {
                    labeledCopyableText("Structured Spec", specSummary(spec))
                }
            }
            .padding(22)
        }
    }

    private func metadata(_ revision: PromptRevision) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Revision metadata")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text("Schema \(revision.schemaVersion)")
                if let profileID = revision.profileID {
                    Text("Profile: \(profileID)\(revision.profileVersion.map { " v\($0)" } ?? "")")
                }
                if let modelName = revision.modelName {
                    Text("Model: \(modelName)\(revision.modelVersion.map { " (\($0))" } ?? "")")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func labeledText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func labeledCopyableText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { onCopy(value) }
                    .buttonStyle(.borderless)
                    .disabled(value.isEmpty)
            }
            Text(value.isEmpty ? "No text" : value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func specSummary(_ spec: PromptSpec) -> String {
        var sections = ["Title: \(spec.title)", "Objective: \(spec.objective)", "Output: \(spec.outputContract)"]
        if !spec.context.isEmpty { sections.append("Context: \(spec.context)") }
        if !spec.constraints.isEmpty { sections.append("Constraints:\n• " + spec.constraints.joined(separator: "\n• ")) }
        if !spec.assumptions.isEmpty { sections.append("Assumptions:\n• " + spec.assumptions.joined(separator: "\n• ")) }
        if !spec.acceptanceCriteria.isEmpty { sections.append("Acceptance:\n• " + spec.acceptanceCriteria.joined(separator: "\n• ")) }
        return sections.joined(separator: "\n\n")
    }
}

private struct RevisionRow: View {
    let revision: PromptRevision
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Revision \(revision.revisionNumber)")
                    .font(.subheadline.weight(.semibold))
                if isLatest {
                    Text("Latest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Text(revision.changeSummary.isEmpty ? revision.name : revision.changeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(revision.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
