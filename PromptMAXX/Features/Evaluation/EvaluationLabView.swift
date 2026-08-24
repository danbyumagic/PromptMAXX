import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

/// A transparent evaluation harness for the built-in mechanical benchmark.
/// It reports observed outputs and checks without making subjective judgments.
public struct EvaluationLabView: View {
    public let endpoint: OllamaEndpoint?
    public let models: [OllamaModel]
    public let preferredModel: String
    public let endpointDescription: String
    public let traceStore: TraceStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedModel: String
    @State private var report: EvalReport?
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?
    @State private var runID: UUID?
    @State private var runError: String?
    @State private var tracePersistenceError: String?
    @State private var exportError: String?
    @State private var expandedResults: Set<String> = []

    public init(
        endpoint: OllamaEndpoint?,
        models: [OllamaModel],
        preferredModel: String,
        endpointDescription: String,
        traceStore: TraceStore
    ) {
        self.endpoint = endpoint
        self.models = models
        self.preferredModel = preferredModel
        self.endpointDescription = endpointDescription
        self.traceStore = traceStore
        _selectedModel = State(initialValue: models.contains(where: { $0.model == preferredModel }) ? preferredModel : (models.first?.model ?? ""))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    benchmarkExplanation
                    configurationSection

                    if models.isEmpty {
                        ContentUnavailableView(
                            "No installed models",
                            systemImage: "cpu",
                            description: Text("Refresh the model list in Setup before running the Evaluation Lab.")
                        )
                        .accessibilityLabel("No installed models. Refresh the model list in Setup before running the Evaluation Lab.")
                    }

                    if let runError {
                        errorBanner(runError)
                    }
                    if let tracePersistenceError {
                        errorBanner("Trace persistence failed: \(tracePersistenceError)")
                    }
                    if let exportError {
                        errorBanner("Export failed: \(exportError)")
                    }
                    if isRunning {
                        Label("Running 16 sequential model calls…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Evaluation is running: 16 sequential model calls")
                    }
                    if let report {
                        reportContent(report)
                    }
                }
                .padding()
            }

            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 640)
        .onChange(of: selectedModel) { _, _ in
            clearReport()
        }
        .onDisappear { cancelRun() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Evaluation Lab")
                    .font(.title2.bold())
                Text("Measure transparent, mechanical support-ticket checks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Evaluation Lab")
        }
        .padding()
    }

    private var benchmarkExplanation: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                Label("8 support-ticket cases", systemImage: "ticket")
                    .font(.headline)
                Text(BuiltInBenchmark.suite.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("The original and refined candidates use the same selected model. Results are pass counts, response timing, token metadata, and raw evidence—not a subjective quality score.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Latency includes runtime and possible model warm-up; compare candidates with care rather than treating timing as an absolute quality measure.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                endpointStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var endpointStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: endpoint.map { $0.isLoopback ? "lock.fill" : "network" } ?? "exclamationmark.triangle.fill")
            Text(endpoint == nil ? "Endpoint unavailable" : (endpoint?.isLoopback == true ? "Local Ollama endpoint" : "Remote Ollama endpoint"))
                .font(.caption.weight(.semibold))
            Text(endpointDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .foregroundStyle(endpoint == nil ? .orange : .secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(endpoint == nil ? "Ollama endpoint unavailable" : (endpoint?.isLoopback == true ? "Local Ollama endpoint. \(endpointDescription)" : "Remote Ollama endpoint. \(endpointDescription)"))
    }

    private var configurationSection: some View {
        GroupBox("Run configuration") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Installed model", selection: $selectedModel) {
                    ForEach(models) { model in
                        Text(model.displayName).tag(model.model)
                    }
                }
                .disabled(isRunning || models.isEmpty)
                .accessibilityLabel("Evaluation model")

                Text("Both candidates run against \(selectedModel.isEmpty ? "the selected model" : selectedModel) for a fair mechanical comparison.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Candidate generation options") {
                    VStack(alignment: .leading, spacing: 5) {
                        candidateOptionRow(BuiltInBenchmark.originalCandidate(model: selectedModel))
                        candidateOptionRow(BuiltInBenchmark.refinedCandidate(model: selectedModel))
                    }
                    .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func candidateOptionRow(_ candidate: EvalCandidateConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.label).font(.caption.weight(.semibold))
            Text(optionsDescription(candidate))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.label): \(optionsDescription(candidate))")
    }

    private func optionsDescription(_ candidate: EvalCandidateConfiguration) -> String {
        let options = candidate.generationOptions
        let format = candidate.format?.rawValue ?? "text"
        let seed = options.seed.map(String.init) ?? "none"
        return "temperature \(String(format: "%.2f", options.temperature)) · top-p \(String(format: "%.2f", options.topP)) · max \(options.maxTokens) tokens · seed \(seed) · streaming \(options.stream ? "yes" : "no") · \(format) format"
    }

    @ViewBuilder
    private func reportContent(_ report: EvalReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Observed results")
                    .font(.title3.bold())
                Spacer()
                Text("\(report.suite.cases.count) cases · \(report.candidates.count) candidates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(report.summaries, id: \.candidateID) { summary in
                summaryCard(summary)
            }

            Text("Per-case evidence")
                .font(.title3.bold())
                .padding(.top, 5)
            ForEach(report.candidates) { candidate in
                let results = report.results.filter { $0.candidateID == candidate.id }
                DisclosureGroup(candidate.label) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(results) { result in
                            caseEvidence(result)
                        }
                    }
                    .padding(.top, 5)
                }
                .accessibilityLabel("Evidence for \(candidate.label)")
            }
        }
    }

    private func summaryCard(_ summary: EvalCandidateSummary) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.candidateLabel).font(.headline)
                        Text("Model: \(summary.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(summary.passedCases)/\(summary.totalCases) · \(EvaluationLabFormatting.percentage(summary.passRate))")
                        .font(.headline.monospacedDigit())
                        .accessibilityLabel("\(summary.passedCases) of \(summary.totalCases) passed, \(EvaluationLabFormatting.percentage(summary.passRate))")
                }
                HStack(spacing: 14) {
                    metric("Average latency", value: summary.averageLatencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
                    metric("Average input", value: summary.averageInputTokens.map { String(format: "%.1f tokens", $0) } ?? "—")
                    metric("Average output", value: summary.averageOutputTokens.map { String(format: "%.1f tokens", $0) } ?? "—")
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func caseEvidence(_ result: EvalCaseResult) -> some View {
        DisclosureGroup(isExpanded: expandedBinding(for: result.id)) {
            VStack(alignment: .leading, spacing: 7) {
                if let error = result.error {
                    Label(error, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if !result.checkResults.isEmpty {
                    ForEach(result.checkResults, id: \.checkID) { check in
                        Label("\(check.label): \(check.detail)", systemImage: check.passed ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(check.passed ? .green : .red)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                if let output = result.output {
                    Text(output)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Output: \(output)")
                }
            }
            .padding(.top, 5)
        } label: {
            HStack {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)
                Text(result.caseID).font(.caption.weight(.semibold))
                Spacer()
                Text("\(result.checksPassed)/\(result.checkResults.count) checks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let latency = result.latencyMilliseconds {
                    Text(String(format: "%.0f ms", latency))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel("\(result.caseID), \(result.passed ? "passed" : "failed")")
    }

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedResults.contains(id) },
            set: { expanded in
                if expanded { expandedResults.insert(id) }
                else { expandedResults.remove(id) }
            }
        )
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
                .buttonStyle(.borderless)
            Spacer()
            if report != nil {
                Button("Export JSON") { exportJSON() }
                    .disabled(isRunning)
                Button("Export Markdown") { exportMarkdown() }
                    .disabled(isRunning)
            }
            Button(isRunning ? "Cancel Run" : "Run Evaluation") {
                isRunning ? cancelRun() : startRun()
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .orange : .teal)
            .disabled(!isRunning && (endpoint == nil || selectedModel.isEmpty || models.isEmpty))
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(isRunning ? "Cancel evaluation run" : "Run evaluation")
        }
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
            .accessibilityLabel(message)
    }

    private func startRun() {
        guard let endpoint else {
            runError = "Enter a valid Ollama endpoint in Setup before running the Evaluation Lab."
            return
        }
        guard models.contains(where: { $0.model == selectedModel }) else {
            runError = "Choose an installed model before running the Evaluation Lab."
            return
        }

        cancelRun()
        report = nil
        runError = nil
        tracePersistenceError = nil
        exportError = nil
        expandedResults.removeAll()
        let id = UUID()
        runID = id
        isRunning = true
        let model = selectedModel
        runTask = Task {
            do {
                let client = try OllamaClient(endpoint: endpoint, timeout: 120)
                let runner = EvaluationRunner(provider: client)
                let request = EvalRunRequest(
                    suite: BuiltInBenchmark.suite,
                    candidates: [
                        BuiltInBenchmark.originalCandidate(model: model),
                        BuiltInBenchmark.refinedCandidate(model: model)
                    ]
                )
                let completed = try await runner.run(request) { result in
                    guard !Task.isCancelled else { return }
                    guard let candidate = request.candidates.first(where: { $0.id == result.candidateID }) else {
                        return
                    }
                    await self.persistEvaluationTrace(
                        result: result, suite: request.suite, candidate: candidate,
                        endpointLabel: endpointDescription,
                        endpointLocality: endpoint.isLoopback ? .local : .remote,
                        runID: id
                    )
                }
                guard TracePersistenceGate.permits(
                    capturedToken: id, activeToken: runID, isCancelled: Task.isCancelled
                ) else { return }
                report = completed
            } catch is CancellationError {
                // Cancellation is an intentional user action, not a failed evaluation.
            } catch {
                guard runID == id else { return }
                runError = error.localizedDescription
            }
            guard TracePersistenceGate.permits(
                capturedToken: id, activeToken: runID, isCancelled: Task.isCancelled
            ) else { return }
            runID = nil
            isRunning = false
            runTask = nil
        }
    }

    @MainActor
    private func persistEvaluationTrace(
        result: EvalCaseResult,
        suite: EvalSuite,
        candidate: EvalCandidateConfiguration,
        endpointLabel: String,
        endpointLocality: EndpointLocality,
        runID: UUID
    ) async {
        guard TracePersistenceGate.permits(
            capturedToken: runID, activeToken: self.runID, isCancelled: Task.isCancelled
        ) else { return }
        do {
            let trace = try RunTraceFactory.evaluation(
                result: result, suite: suite, candidate: candidate,
                endpointLabel: endpointLabel, endpointLocality: endpointLocality
            )
            guard TracePersistenceGate.permits(
                capturedToken: runID, activeToken: self.runID, isCancelled: Task.isCancelled
            ) else { return }
            // This is the final stale/cancellation gate. Invoking the serialized
            // append below starts the durable operation; later cancellation does
            // not retract completed evaluation evidence.
            if !(await traceStore.append(trace)) {
                guard self.runID == runID, !Task.isCancelled else { return }
                tracePersistenceError = traceStore.error?.localizedDescription
                    ?? "The trace store rejected an evaluation case."
            }
        } catch {
            guard self.runID == runID, !Task.isCancelled else { return }
            tracePersistenceError = error.localizedDescription
        }
    }

    private func cancelRun() {
        runID = nil
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }

    private func clearReport() {
        report = nil
        exportError = nil
        runError = nil
        expandedResults.removeAll()
    }

    private func exportJSON() {
        guard let report else { return }
        export(report: report, fileExtension: "json", contentType: .json) { try report.jsonData() }
    }

    private func exportMarkdown() {
        guard let report else { return }
        export(report: report, fileExtension: "md", contentType: .plainText) {
            Data(EvaluationLabFormatting.markdown(report: report).utf8)
        }
    }

    private func export(
        report: EvalReport,
        fileExtension: String,
        contentType: UTType,
        data: () throws -> Data
    ) {
        exportError = nil
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = EvaluationLabFormatting.filename(
            suiteID: report.suiteID, fileExtension: fileExtension)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data().write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
