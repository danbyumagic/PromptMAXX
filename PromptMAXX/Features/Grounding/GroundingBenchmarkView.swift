import SwiftUI
import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// A small, explicit retrieval benchmark surface. It reports ranking
/// outcomes only; it does not generate answers, assign confidence, or make
/// claims about answer quality.
public struct GroundingBenchmarkView: View {
  public let runner: GroundingBenchmarkRunner
  public let suite: GroundingBenchmarkSuite
  public let isRemoteEndpoint: Bool

  @Environment(\.dismiss) private var dismiss
  @State private var embeddingModel: String
  @State private var dimensionsText: String
  @State private var chunkSize = 800
  @State private var overlap = 120
  @State private var lexicalWeight = 0.15
  @State private var mmrLambda = 0.75
  @State private var sameSourcePenalty = 0.1
  @State private var topK = 3
  @State private var characterBudget = 2_000
  @State private var split: GroundingBenchmarkSplit = .heldOut
  @State private var report: GroundingBenchmarkReport?
  @State private var progress: GroundingBenchmarkProgress?
  @State private var failureMessage: String?
  @State private var runTask: Task<Void, Never>?
  @State private var activeRunID: UUID?
  @State private var didCopy = false
  @State private var exportMessage: String?

  public init(
    runner: GroundingBenchmarkRunner,
    suite: GroundingBenchmarkSuite,
    initialEmbeddingModel: String = "",
    initialDimensions: Int? = nil,
    isRemoteEndpoint: Bool
  ) {
    self.runner = runner
    self.suite = suite
    self.isRemoteEndpoint = isRemoteEndpoint
    _embeddingModel = State(initialValue: initialEmbeddingModel)
    _dimensionsText = State(initialValue: initialDimensions.map(String.init) ?? "")
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          suiteSummary
          privacyNotice
          configurationSection
          actionSection
          if let failureMessage {
            failureSection(failureMessage)
          }
          if let report {
            reportSection(report)
          }
        }
        .padding(24)
        .frame(maxWidth: 900, alignment: .leading)
      }
    }
    .frame(minWidth: 760, minHeight: 680)
    .onDisappear {
      activeRunID = nil
      runTask?.cancel()
    }
  }

  private var privacyNotice: some View {
    Label {
      Text(isRemoteEndpoint
        ? "Remote endpoint: benchmark source text and queries are sent over HTTP and may leave this Mac. Use a trusted network or encrypted tunnel."
        : "Local endpoint classification: benchmark source text and queries are sent to the endpoint marked local.")
    } icon: {
      Image(systemName: isRemoteEndpoint ? "network" : "lock.shield")
    }
    .font(.callout)
    .foregroundStyle(isRemoteEndpoint ? .orange : .secondary)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background((isRemoteEndpoint ? Color.orange : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel(isRemoteEndpoint
      ? "Remote endpoint. Benchmark source text and queries may leave this Mac over HTTP."
      : "Local endpoint classification. Benchmark text is sent to the endpoint marked local.")
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("Grounding Benchmark")
          .font(.title2.bold())
        Text("Retrieval measurements for a versioned demo suite")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Close") { dismiss() }
        .buttonStyle(.bordered)
        .accessibilityLabel("Close Grounding Benchmark")
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
  }

  private var suiteSummary: some View {
    GroupBox("Suite") {
      VStack(alignment: .leading, spacing: 6) {
        Text(suite.name)
          .font(.headline)
        Text("\(suite.id) · version \(suite.version) · \(suite.corpus.sources.count) deterministic sources")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("\(suite.tuningCount) tuning queries · \(suite.heldOutCount) held-out queries")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("The benchmark measures retrieval ranking signals only. It does not score confidence or answer quality.")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var configurationSection: some View {
    GroupBox("Configuration") {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          TextField("Embedding model", text: $embeddingModel)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Benchmark embedding model")
            .help("The embedding model used only for this benchmark run")
          TextField("Dimensions (optional)", text: $dimensionsText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .accessibilityLabel("Embedding dimensions, optional")
        }
        Picker("Split", selection: $split) {
          Text("Tuning").tag(GroundingBenchmarkSplit.tuning)
          Text("Held-out").tag(GroundingBenchmarkSplit.heldOut)
          Text("All").tag(GroundingBenchmarkSplit.all)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Benchmark query split")
        HStack {
          Stepper("Top k: \(topK)", value: $topK, in: 1...20)
          Stepper("Character budget: \(characterBudget)", value: $characterBudget, in: 500...50_000, step: 500)
        }
        .accessibilityElement(children: .contain)
        HStack {
          Stepper("Chunk size: \(chunkSize)", value: $chunkSize, in: 100...4_000, step: 50)
          Stepper("Overlap: \(overlap)", value: $overlap, in: 0...1_000, step: 10)
        }
        .accessibilityElement(children: .contain)
        HStack(spacing: 16) {
          parameterSlider(title: "Lexical weight", value: $lexicalWeight)
          parameterSlider(title: "MMR lambda", value: $mmrLambda)
          parameterSlider(title: "Source penalty", value: $sameSourcePenalty, upperBound: 1)
        }
        Text("Chunking and retriever settings are recorded in the exported report.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func parameterSlider(
    title: String, value: Binding<Double>, upperBound: Double = 1
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("\(title): \(String(format: "%.2f", value.wrappedValue))")
        .font(.caption)
      Slider(value: value, in: 0...upperBound, step: 0.01)
        .accessibilityLabel(title)
    }
    .frame(maxWidth: .infinity)
  }

  private var actionSection: some View {
    HStack(spacing: 10) {
      if runTask != nil {
        Button("Stop", systemImage: "stop.circle") {
          activeRunID = nil
          runTask?.cancel()
          runTask = nil
          failureMessage = "Benchmark cancelled."
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Stop benchmark")
      } else {
        Button("Run Benchmark", systemImage: "play.fill") {
          startRun()
        }
        .buttonStyle(.borderedProminent)
        .disabled(embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Run grounding benchmark")
      }
      if let progress {
        ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
          .frame(width: 160)
          .accessibilityLabel(progressLabel(progress))
        Text(progressLabel(progress))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if let exportMessage {
        Text(exportMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func failureSection(_ message: String) -> some View {
    Label {
      Text(message)
        .textSelection(.enabled)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel("Benchmark failure: \(message)")
  }

  private func reportSection(_ report: GroundingBenchmarkReport) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Report")
          .font(.title3.bold())
        Spacer()
        Button("Copy JSON", systemImage: "doc.on.doc") { copy(jsonText(report)) }
          .buttonStyle(.borderless)
          .accessibilityLabel("Copy benchmark JSON")
        Button("Copy Markdown", systemImage: "doc.on.clipboard") { copy(report.markdown()) }
          .buttonStyle(.borderless)
          .accessibilityLabel("Copy benchmark Markdown")
        #if os(macOS)
        Button("Save JSON…", systemImage: "square.and.arrow.down") { saveJSON(report) }
          .buttonStyle(.borderless)
          .accessibilityLabel("Save benchmark JSON")
        #endif
      }
      Text("Completed \(report.metadata.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown time")")
        .font(.caption)
        .foregroundStyle(.secondary)
      metricsGrid(report.aggregate)
      caseList(report.outcomes)
    }
  }

  private func jsonText(_ report: GroundingBenchmarkReport) -> String {
    guard let data = try? report.jsonData(), let text = String(data: data, encoding: .utf8) else {
      return "Unable to encode benchmark JSON."
    }
    return text
  }

  private func metricsGrid(_ aggregate: GroundingBenchmarkAggregate) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
      metric("Hit rate @ k", value: percent(aggregate.hitRateAtK))
      metric("Mean recall @ k", value: percent(aggregate.recallAtK))
      metric("Source coverage", value: percent(aggregate.sourceCoverage))
      metric("Zero-result cases", value: "\(aggregate.zeroResultCount)")
      metric("Errors", value: "\(aggregate.errorCount)")
      metric("Evaluated / total", value: "\(aggregate.evaluatedCases) / \(aggregate.totalCases)")
    }
  }

  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.headline.monospacedDigit())
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }

  private func caseList(_ outcomes: [GroundingBenchmarkCaseOutcome]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Per-case outcomes")
        .font(.headline)
      ForEach(outcomes) { outcome in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(outcome.id).font(.caption.monospaced())
            Text(outcome.split.displayName).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(outcome.status.rawValue)
              .font(.caption)
              .foregroundStyle(outcome.status == .error ? .red : .secondary)
          }
          Text(outcome.query).font(.callout)
          Text("Hit @ k: \(outcome.hitAtK ? "yes" : "no") · Recall @ k: \(percent(outcome.recallAtK)) · Sources: \(outcome.retrievedSourceIDs.isEmpty ? "none" : outcome.retrievedSourceIDs.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
          if let errorMessage = outcome.errorMessage {
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caseAccessibilityLabel(outcome))
      }
    }
  }

  private func startRun() {
    runTask?.cancel()
    let dimensions: Int?
    if dimensionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      dimensions = nil
    } else if let value = Int(dimensionsText), value > 0 {
      dimensions = value
    } else {
      failureMessage = "Dimensions must be a positive integer or blank."
      return
    }
    let configuration: GroundingBenchmarkConfiguration
    do {
      configuration = try GroundingBenchmarkConfiguration(
        embeddingModel: embeddingModel,
        dimensions: dimensions,
        chunkSize: chunkSize,
        overlap: overlap,
        lexicalWeight: lexicalWeight,
        mmrLambda: mmrLambda,
        sameSourcePenalty: sameSourcePenalty,
        topK: topK,
        characterBudget: characterBudget,
        split: split,
        endpointLocality: isRemoteEndpoint ? .remote : .local)
    } catch {
      failureMessage = error.localizedDescription
      return
    }
    let operationID = UUID()
    activeRunID = operationID
    report = nil
    failureMessage = nil
    exportMessage = nil
    progress = nil
    runTask = Task {
      do {
        let result = try await runner.run(
          suite: suite,
          configuration: configuration,
          progress: { value in
            Task { @MainActor in
              guard self.activeRunID == operationID else { return }
              self.progress = value
            }
          })
        guard !Task.isCancelled else { return }
        guard self.activeRunID == operationID else { return }
        self.report = result
        self.runTask = nil
      } catch is CancellationError {
        guard self.activeRunID == operationID else { return }
        self.failureMessage = "Benchmark cancelled."
        self.runTask = nil
      } catch {
        guard self.activeRunID == operationID else { return }
        self.failureMessage = error.localizedDescription
        self.runTask = nil
      }
    }
  }

  private func progressLabel(_ progress: GroundingBenchmarkProgress) -> String {
    switch progress.phase {
    case .embeddingCorpus:
      return "Embedding corpus \(progress.completed) of \(progress.total)"
    case .evaluatingQueries:
      if let currentQueryID = progress.currentQueryID {
        return "Evaluating \(currentQueryID), \(progress.completed) of \(progress.total)"
      }
      return "Evaluating queries \(progress.completed) of \(progress.total)"
    }
  }

  private func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
  }

  private func caseAccessibilityLabel(_ outcome: GroundingBenchmarkCaseOutcome) -> String {
    "\(outcome.id), \(outcome.query), \(outcome.status.rawValue), hit at k \(outcome.hitAtK ? "yes" : "no"), recall at k \(percent(outcome.recallAtK))"
  }

  private func copy(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
    didCopy = true
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      didCopy = false
    }
  }

  #if os(macOS)
  private func saveJSON(_ report: GroundingBenchmarkReport) {
    guard let data = try? report.jsonData() else {
      exportMessage = "Could not encode JSON."
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "grounding-benchmark.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try data.write(to: url, options: .atomic)
      exportMessage = "Saved benchmark JSON."
    } catch {
      exportMessage = "Save failed: \(error.localizedDescription)"
    }
  }
  #endif
}
