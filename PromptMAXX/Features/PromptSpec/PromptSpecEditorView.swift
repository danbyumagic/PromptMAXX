//
//  PromptSpecEditorView.swift
//  PromptMAXX
//

import SwiftUI

/// A local-draft editor for a structured PromptSpec. Changes are not exposed
/// to the caller until Apply succeeds; dismissing the view is a true cancel.
public struct PromptSpecEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PromptSpec

    private let profileName: String
    private let onApply: (PromptSpec) -> Void

    public init(
        spec: PromptSpec,
        profileName: String,
        onApply: @escaping (PromptSpec) -> Void
    ) {
        _draft = State(initialValue: spec)
        self.profileName = profileName
        self.onApply = onApply
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    editorSection(
                        title: "Title",
                        hint: "A short name for this prompt specification.",
                        content: {
                            TextField("Prompt title", text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Prompt title")
                        }
                    )

                    editorSection(
                        title: "Objective",
                        hint: "What should the model help accomplish?",
                        content: {
                            textEditor(
                                placeholder: "Describe the intended outcome…",
                                text: $draft.objective,
                                accessibilityLabel: "Prompt objective"
                            )
                        }
                    )

                    editorSection(
                        title: "Context",
                        hint: "Relevant background, audience, or inputs.",
                        content: {
                            textEditor(
                                placeholder: "Add background or situational context…",
                                text: $draft.context,
                                accessibilityLabel: "Prompt context",
                                minHeight: 100
                            )
                        }
                    )

                    listEditor(
                        title: "Constraints",
                        hint: "One constraint per line.",
                        text: listBinding(\.constraints),
                        accessibilityLabel: "Prompt constraints"
                    )

                    listEditor(
                        title: "Assumptions",
                        hint: "One assumption per line.",
                        text: listBinding(\.assumptions),
                        accessibilityLabel: "Prompt assumptions"
                    )

                    listEditor(
                        title: "Missing Questions",
                        hint: "Open questions that may need answers before execution.",
                        text: listBinding(\.missingQuestions),
                        accessibilityLabel: "Missing prompt questions"
                    )

                    editorSection(
                        title: "Output Contract",
                        hint: "Describe the required format, voice, and boundaries of the answer.",
                        content: {
                            textEditor(
                                placeholder: "Define what a successful response must look like…",
                                text: $draft.outputContract,
                                accessibilityLabel: "Prompt output contract",
                                minHeight: 100
                            )
                        }
                    )

                    listEditor(
                        title: "Acceptance Criteria",
                        hint: "One criterion per line.",
                        text: listBinding(\.acceptanceCriteria),
                        accessibilityLabel: "Prompt acceptance criteria"
                    )

                    validationSection
                    previewSection
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()
            actionBar
        }
        .background(.background)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 680, idealHeight: 760)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Specification")
                    .font(.title2.weight(.semibold))
                Text("Profile · \(profileName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prompt specification editor, profile \(profileName)")
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if !draft.validationIssues.isEmpty {
                Label("Complete required fields to apply", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Prompt specification has validation issues")
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cancel prompt specification edits")

            Button("Apply") {
                apply()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.validationIssues.isEmpty)
            .accessibilityLabel("Apply prompt specification edits")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func editorSection<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(title: title, hint: hint)
            content()
        }
    }

    private func listEditor(
        title: String,
        hint: String,
        text: Binding<String>,
        accessibilityLabel: String
    ) -> some View {
        editorSection(title: title, hint: hint) {
            textEditor(
                placeholder: "Add one item per line…",
                text: text,
                accessibilityLabel: accessibilityLabel,
                minHeight: 86
            )
        }
    }

    private func sectionHeading(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func textEditor(
        placeholder: String,
        text: Binding<String>,
        accessibilityLabel: String,
        minHeight: CGFloat = 86
    ) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .accessibilityLabel(accessibilityLabel)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .padding(.top, 3)
                    .allowsHitTesting(false)
            }
        }
        .padding(8)
        .frame(minHeight: minHeight)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(
                title: "Validation",
                hint: "Required fields are checked before the specification can be applied."
            )

            if draft.validationIssues.isEmpty {
                Label("Ready to apply", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.validationIssues.indices, id: \.self) { index in
                        let issue = draft.validationIssues[index]
                        Label {
                            Text("\(issue.field): \(issue.message)")
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Prompt validation issues")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeading(
                    title: "Compiled Preview",
                    hint: "Deterministic plain-text rendering sent to the model."
                )
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            ScrollView {
                Text(compiledPreview)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel("Compiled prompt preview")
            }
            .frame(minHeight: 130, maxHeight: 220)
            .padding(12)
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var compiledPreview: String {
        (try? PromptCompiler().compile(draft)) ?? draft.compiledPrompt
    }

    private func listBinding(_ keyPath: WritableKeyPath<PromptSpec, [String]>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath].joined(separator: "\n") },
            set: { value in
                draft[keyPath: keyPath] = value
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func apply() {
        let normalized = draft.normalized
        guard normalized.validationIssues.isEmpty else { return }
        onApply(normalized)
        dismiss()
    }
}

#Preview {
    PromptSpecEditorView(
        spec: PromptSpec(
            title: "Release notes",
            objective: "Turn engineering changes into concise release notes.",
            context: "The audience is a product team.",
            constraints: ["Use plain language", "Keep it under 200 words"],
            outputContract: "Return Markdown with a heading and bullet list.",
            acceptanceCriteria: ["Every change is represented", "No unsupported claims"]
        ),
        profileName: "Structured",
        onApply: { _ in }
    )
}
