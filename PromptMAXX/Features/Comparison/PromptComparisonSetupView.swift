import SwiftUI

/// Configures two to four model/profile candidates before a local comparison run.
public struct PromptComparisonSetupView: View {
    private struct CandidateDraft: Identifiable {
        let id: UUID
        var model: String
        var profileID: String

        init(model: String, profileID: String) {
            id = UUID()
            self.model = model
            self.profileID = profileID
        }
    }

    public let sourceText: String
    public let models: [OllamaModel]
    public let profiles: [PromptProfile]
    public let endpointDescription: String
    public let onStart: (PromptComparisonConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [CandidateDraft]
    @State private var validationMessage: String?

    public init(
        sourceText: String,
        models: [OllamaModel],
        preferredModel: String? = nil,
        customProfile: PromptProfile,
        endpointDescription: String,
        onStart: @escaping (PromptComparisonConfiguration) -> Void
    ) {
        self.sourceText = sourceText
        self.models = models
        profiles = PromptProfile.builtIns + [customProfile]
        self.endpointDescription = endpointDescription
        self.onStart = onStart

        let names = models.map(\.model)
        let first = preferredModel.flatMap { names.contains($0) ? $0 : nil } ?? names.first ?? ""
        let second = names.dropFirst().first ?? first
        _drafts = State(initialValue: [
            CandidateDraft(model: first, profileID: PromptProfile.concise.id),
            CandidateDraft(model: second, profileID: PromptProfile.structured.id)
        ])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Sequential, resource-aware comparison", systemImage: "lock.shield")
                                .font(.headline)
                            Text("Candidates run one at a time against the configured Ollama endpoint. This keeps local memory and thermal use predictable; no quality score is inferred.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(endpointDescription)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if models.isEmpty {
                        ContentUnavailableView("No installed models", systemImage: "cpu", description: Text("Refresh the model list in Setup before comparing candidates."))
                    } else {
                        ForEach($drafts) { $draft in
                            candidateEditor($draft)
                        }

                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Button {
                                addCandidate()
                            } label: {
                                Label("Add Candidate", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(drafts.count >= 4)

                            if drafts.count > 2 {
                                Button("Remove Last", role: .destructive) {
                                    drafts.removeLast()
                                    validationMessage = nil
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Compare Candidates", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(models.isEmpty || drafts.count < 2)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 500)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.split.2x1")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare Candidates")
                    .font(.title2.bold())
                Text("Run the same source prompt through different model/profile pairings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private func candidateEditor(_ draft: Binding<CandidateDraft>) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Candidate \(drafts.firstIndex { $0.id == draft.wrappedValue.id }.map { $0 + 1 } ?? 1)")
                    .font(.headline)
                HStack(spacing: 14) {
                    Picker("Model", selection: draft.model) {
                        ForEach(models) { model in
                            Text(model.model).tag(model.model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Picker("Profile", selection: draft.profileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                Text(profileDescription(for: draft.wrappedValue.profileID))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func profileDescription(for id: String) -> String {
        profiles.first(where: { $0.id == id })?.description ?? ""
    }

    private func addCandidate() {
        guard drafts.count < 4 else { return }
        let model = models.first?.model ?? ""
        let profile = profiles[drafts.count % profiles.count].id
        drafts.append(CandidateDraft(model: model, profileID: profile))
        validationMessage = nil
    }

    private func start() {
        do {
            let pairings = drafts.map { "\($0.model)\u{1F} \($0.profileID)" }
            guard Set(pairings).count == pairings.count else {
                throw PromptComparisonError.invalidConfiguration("Each model/profile pairing must be unique.")
            }
            let candidates = try drafts.enumerated().map { index, draft in
                guard let profile = profiles.first(where: { $0.id == draft.profileID }) else {
                    throw PromptComparisonError.invalidConfiguration("Choose a profile for every candidate.")
                }
                return try PromptComparisonCandidate(
                    id: "candidate-\(index + 1)",
                    model: draft.model,
                    profile: profile
                )
            }
            onStart(try PromptComparisonConfiguration(sourceText: sourceText, candidates: candidates))
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
