import SwiftUI
import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// A factual inspector for the indexed grounding corpus and retrieval signals.
/// It deliberately stops at retrieval: it does not generate answers or claim
/// that a ranking score represents confidence or source quality.
public struct GroundingInspectorView: View {
  public let store: GroundingStore
  public let isRemoteEndpoint: Bool

  @Environment(\.dismiss) private var dismiss
  @State private var embeddingModel = "nomic-embed-text"
  @State private var query = ""
  @State private var topK = 5
  @State private var characterBudget = 4_000
  @State private var isImporterPresented = false
  @State private var sourceToDelete: GroundingSourceSummary?
  @State private var isClearConfirmationPresented = false
  @State private var importError: String?
  @State private var selectedMatchID: String?
  @State private var didCopy = false
  @State private var indexTask: Task<Void, Never>?
  @State private var importOperationID: UUID?
  @State private var retrievalTask: Task<Void, Never>?
  @State private var mutationTask: Task<Void, Never>?
  @State private var isDiscardConfirmationPresented = false
  @State private var benchmarkRunner: GroundingBenchmarkRunner?
  @State private var benchmarkSuite: GroundingBenchmarkSuite?
  @State private var benchmarkPreparationTask: Task<Void, Never>?
  @State private var benchmarkPreparationID: UUID?
  @State private var isBenchmarkPresented = false
  @State private var benchmarkPreparationError: String?

  public init(store: GroundingStore, isRemoteEndpoint: Bool) {
    self.store = store
    self.isRemoteEndpoint = isRemoteEndpoint
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        privacyNotice
        sourceSection
        retrievalSection
        if let result = store.retrievalResult {
          resultsSection(result)
        }
      }
      .padding(24)
      .frame(maxWidth: 900, alignment: .leading)
    }
    .frame(minWidth: 680, minHeight: 620)
    .fileImporter(
      isPresented: $isImporterPresented,
      allowedContentTypes: supportedContentTypes,
      allowsMultipleSelection: false,
      onCompletion: handleImport
    )
    .alert("Delete Indexed Source?", isPresented: Binding(
      get: { sourceToDelete != nil },
      set: { if !$0 { sourceToDelete = nil } }
    ), presenting: sourceToDelete) { summary in
      Button("Delete", role: .destructive) {
        sourceToDelete = nil
        mutationTask?.cancel()
        mutationTask = Task { _ = await store.deleteSource(id: summary.sourceID) }
      }
      Button("Cancel", role: .cancel) { sourceToDelete = nil }
    } message: { summary in
      Text("Remove \(summary.sourceName) and its \(summary.chunkCount) indexed chunks? The source file will not be deleted.")
    }
    .alert("Clear Grounding Index?", isPresented: $isClearConfirmationPresented) {
      Button("Clear Index", role: .destructive) {
        mutationTask?.cancel()
        mutationTask = Task { _ = await store.clear() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes every indexed source and cannot be undone from this inspector.")
    }
    .alert("Discard Unreadable Index?", isPresented: $isDiscardConfirmationPresented) {
      Button("Discard Index", role: .destructive) {
        mutationTask?.cancel()
        mutationTask = Task { _ = await store.discard() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The persisted grounding index cannot be read. Discarding it removes the corrupt file and starts an empty index; original source files are not deleted.")
    }
    .sheet(isPresented: $isBenchmarkPresented, onDismiss: {
      benchmarkRunner = nil
      benchmarkSuite = nil
    }) {
      if let benchmarkRunner, let benchmarkSuite {
        GroundingBenchmarkView(
          runner: benchmarkRunner,
          suite: benchmarkSuite,
          initialEmbeddingModel: store.selectedEmbeddingModel,
          initialDimensions: store.selectedEmbeddingDimension,
          isRemoteEndpoint: isRemoteEndpoint
        )
      } else {
        ProgressView("Preparing benchmark…")
          .frame(width: 420, height: 220)
      }
    }
    .alert("Benchmark Unavailable", isPresented: Binding(
      get: { benchmarkPreparationError != nil },
      set: { if !$0 { benchmarkPreparationError = nil } }
    )) {
      Button("OK", role: .cancel) { benchmarkPreparationError = nil }
    } message: {
      Text(benchmarkPreparationError ?? "The benchmark suite could not be prepared.")
    }
    .onDisappear {
      importOperationID = nil
      indexTask?.cancel()
      retrievalTask?.cancel()
      mutationTask?.cancel()
      benchmarkPreparationID = nil
      benchmarkPreparationTask?.cancel()
    }
    .task {
      await store.loadIfNeeded()
      if !store.selectedEmbeddingModel.isEmpty {
        embeddingModel = store.selectedEmbeddingModel
      }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Context Inspector")
          .font(.title2.bold())
        Text("Inspect indexed text and transparent retrieval signals.")
          .foregroundStyle(.secondary)
      }
      Spacer()
      HStack(spacing: 8) {
        Button("Benchmark", systemImage: "chart.bar.xaxis") {
          prepareBenchmark()
        }
        .buttonStyle(.bordered)
        .disabled(benchmarkPreparationTask != nil)
        .accessibilityLabel("Run grounding benchmark")
        .accessibilityHint("Evaluate retrieval against the built-in tuning or held-out query suite")
        Button("Close") { dismiss() }
          .buttonStyle(.bordered)
          .accessibilityLabel("Close Context Inspector")
        Button("Import Text…", systemImage: "doc.badge.plus") {
          isImporterPresented = true
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isBusy || store.state == .failed)
        .accessibilityLabel("Import UTF-8 text or Markdown source")
        .accessibilityHint("PDF files are not supported")
      }
    }
  }

  private func prepareBenchmark() {
    benchmarkPreparationTask?.cancel()
    let operationID = UUID()
    benchmarkPreparationID = operationID
    benchmarkPreparationError = nil
    benchmarkPreparationTask = Task {
      do {
        let suite = try GroundingBenchmarkSuite.makeDemo()
        let runner = await store.service.makeBenchmarkRunner()
        guard !Task.isCancelled, benchmarkPreparationID == operationID else { return }
        benchmarkSuite = suite
        benchmarkRunner = runner
        isBenchmarkPresented = true
        benchmarkPreparationTask = nil
      } catch {
        guard benchmarkPreparationID == operationID else { return }
        benchmarkPreparationError = error.localizedDescription
        benchmarkPreparationTask = nil
      }
    }
  }

  private var privacyNotice: some View {
    Label {
      Text(isRemoteEndpoint
        ? "Remote endpoint: source text and queries are sent over HTTP and may leave this Mac. Use a trusted network or encrypted tunnel."
        : "Local endpoint classification: the configured embedding endpoint is marked local.")
    } icon: {
      Image(systemName: isRemoteEndpoint ? "network" : "lock.shield")
    }
    .font(.callout)
    .foregroundStyle(isRemoteEndpoint ? .orange : .secondary)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background((isRemoteEndpoint ? Color.orange : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel(isRemoteEndpoint
      ? "Remote endpoint. Source text and queries are sent over HTTP and may leave this Mac. Use a trusted network or encrypted tunnel."
      : "Local endpoint classification. The configured embedding endpoint is marked local.")
    .help("This notice reflects the endpoint classification supplied by the caller.")
  }

  private var sourceSection: some View {
    GroupBox("Indexed sources") {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          TextField("Embedding model", text: $embeddingModel)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Embedding model")
            .help("The embedding model used for indexing and retrieval")
          if store.isBusy {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("Grounding operation in progress")
          }
        }
        if !store.selectedEmbeddingModel.isEmpty {
          VStack(alignment: .leading, spacing: 2) {
            Text("Indexed identity: \(store.selectedEmbeddingModel) · \(store.selectedEmbeddingDimension.map(String.init) ?? "unknown") dimensions")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("Changing the embedding model or endpoint requires clearing and rebuilding this index.")
              .font(.caption)
              .foregroundStyle(.orange)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Indexed identity \(store.selectedEmbeddingModel), \(store.selectedEmbeddingDimension.map(String.init) ?? "unknown") dimensions. Changing the embedding model or endpoint requires clearing and rebuilding this index.")
        }

        if let progress = store.indexProgress, store.isBusy {
          VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(progress.completedChunks), total: Double(max(progress.totalChunks, 1)))
            Text("Indexing \(progress.completedChunks) of \(progress.totalChunks) chunks")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Indexing \(progress.completedChunks) of \(progress.totalChunks) chunks")
        }

        if store.isLoading {
          ProgressView("Loading index…")
        } else {
          if let error = store.indexError {
            let isUnavailable = store.state == .failed
            errorState(
              title: isUnavailable ? "Index unavailable" : "Index operation reported a problem",
              message: error.localizedDescription,
              actionTitle: isUnavailable ? "Retry" : "Dismiss"
            ) {
              if isUnavailable {
                mutationTask?.cancel()
                mutationTask = Task { await store.retry() }
              } else {
                store.clearErrors()
              }
            }
            if isUnavailable {
              Button("Discard Corrupt Index…", systemImage: "trash", role: .destructive) {
                isDiscardConfirmationPresented = true
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Discard unreadable grounding index")
              .help("Permanently remove the unreadable index and start empty")
            }
          }
          if store.sourceSummaries.isEmpty {
            ContentUnavailableView(
              "No indexed sources",
              systemImage: "books.vertical",
              description: Text("Import a UTF-8 .txt, .md, or .markdown file to create an index.")
            )
            .frame(maxWidth: .infinity)
          } else {
            ForEach(store.sourceSummaries) { summary in
              sourceRow(summary)
            }
            HStack {
              Text("\(store.sourceSummaries.count) source\(store.sourceSummaries.count == 1 ? "" : "s") indexed")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("Clear Index", systemImage: "trash") {
                isClearConfirmationPresented = true
              }
              .buttonStyle(.borderless)
              .foregroundStyle(.red)
              .disabled(store.isBusy)
              .accessibilityLabel("Clear all indexed sources")
            }
          }
        }

        if let importError {
          errorState(title: "Import failed", message: importError, actionTitle: "Dismiss") {
            self.importError = nil
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func sourceRow(_ summary: GroundingSourceSummary) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "doc.text")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(summary.sourceName)
          .font(.headline)
        Text("Version \(summary.sourceVersion) · \(summary.chunkCount) chunks")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Delete", systemImage: "trash") {
        sourceToDelete = summary
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(.red)
      .disabled(store.isBusy)
      .accessibilityLabel("Delete indexed source \(summary.sourceName)")
      .help("Remove this source from the index; the original file is not deleted")
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .contain)
  }

  private var retrievalSection: some View {
    GroupBox("Retrieve context") {
      VStack(alignment: .leading, spacing: 10) {
        TextEditor(text: $query)
          .font(.body)
          .frame(minHeight: 80, maxHeight: 130)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
          .accessibilityLabel("Retrieval query")
          .accessibilityHint("Enter a question or search phrase for indexed text")

        HStack {
          Stepper("Top results: \(topK)", value: $topK, in: 1...20)
            .accessibilityLabel("Top results limit, \(topK)")
          Spacer()
          Stepper("Character budget: \(characterBudget)", value: $characterBudget, in: 256...20_000, step: 256)
            .accessibilityLabel("Estimated character budget, \(characterBudget)")
        }
        Text("The budget limits estimated envelope size; ranking values are signals for inspection, not confidence scores.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let error = store.retrievalError {
          errorState(title: "Retrieval failed", message: error.localizedDescription, actionTitle: "Dismiss") {
            store.clearErrors()
          }
        }

        Button("Retrieve", systemImage: "magnifyingglass") {
          selectedMatchID = nil
          retrievalTask?.cancel()
          retrievalTask = Task {
            await store.retrieve(
              query: query,
              embeddingModel: embeddingModel,
              dimensions: store.selectedEmbeddingDimension,
              topK: topK,
              characterBudget: characterBudget
            )
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isBusy || store.state == .failed || store.sourceSummaries.isEmpty ||
          query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
          embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Retrieve indexed context")
        .accessibilityHint("Finds and displays the highest-ranked matching chunks")
      }
    }
  }

  private func resultsSection(_ result: GroundingRetrievalResult) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      GroupBox {
        HStack {
          Label("Retrieved \(result.matches.count) match\(result.matches.count == 1 ? "" : "es")", systemImage: "list.number")
            .font(.headline)
          Spacer()
          Text("Model: \(result.embeddingModel) · \(result.dimension) dimensions")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      ForEach(Array(result.matches.enumerated()), id: \.element.id) { index, match in
        matchCard(match, rank: index + 1)
      }

      envelopeSection(result.envelope)
    }
  }

  private func matchCard(_ match: GroundingMatch, rank: Int) -> some View {
    let provenance = match.chunk.provenance
    let isSelected = selectedMatchID == match.id
    return GroupBox {
      VStack(alignment: .leading, spacing: 9) {
        Button {
          selectedMatchID = isSelected ? nil : match.id
        } label: {
          HStack(alignment: .firstTextBaseline) {
            Text("Match \(rank): \(provenance.sourceName)")
              .font(.headline)
            Spacer()
            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
              .font(.caption)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Match \(rank), \(provenance.sourceName), \(GroundingInspectorFormatting.location(provenance))")
        .accessibilityHint(isSelected ? "Hide exact chunk text" : "Show exact chunk text and ranking signals")

        HStack(spacing: 12) {
          Text(GroundingInspectorFormatting.location(provenance))
          Text("Chunk ID \(match.id.prefix(12))…")
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if isSelected {
          VStack(alignment: .leading, spacing: 8) {
            rankingSignal("Combined ranking signal", value: match.score)
            rankingSignal("Semantic ranking signal", value: match.semanticScore)
            rankingSignal("Lexical ranking signal", value: match.lexicalScore)
            rankingSignal("MMR contribution signal", value: match.mmrContribution)
            Text("Exact chunk text")
              .font(.subheadline.bold())
            Text(match.chunk.text)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
              .accessibilityLabel("Exact chunk text: \(match.chunk.text)")
          }
        }
      }
    }
  }

  private func rankingSignal(_ label: String, value: Double) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(GroundingInspectorFormatting.score(value))
        .font(.system(.body, design: .monospaced))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label): \(GroundingInspectorFormatting.score(value))")
  }

  private func envelopeSection(_ envelope: GroundingContextEnvelope) -> some View {
    GroupBox("Generated context envelope preview") {
      VStack(alignment: .leading, spacing: 10) {
        Text("Reference text is untrusted data delimited for a later model call. This inspector does not generate an answer or treat embedded text as instructions.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(envelope.prompt)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
          .accessibilityLabel("Generated context envelope preview")
        HStack {
          Button(didCopy ? "Copied" : "Copy Envelope", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
            copyToClipboard(envelope.prompt)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel(didCopy ? "Envelope copied" : "Copy generated context envelope")
          Spacer()
          Text("Approx. \(envelope.prompt.count) characters")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func errorState(
    title: String,
    message: String,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .font(.headline)
      Text(message)
        .font(.callout)
        .textSelection(.enabled)
      Button(actionTitle) { action() }
        .buttonStyle(.borderless)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
  }

  private var supportedContentTypes: [UTType] {
    [.plainText] + ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      if (error as NSError).code != NSUserCancelledError {
        importError = error.localizedDescription
      }
    case .success(let urls):
      guard let url = urls.first else { return }
      let didAccess = url.startAccessingSecurityScopedResource()
      let operationID = UUID()
      importOperationID = operationID
      importError = nil
      indexTask?.cancel()
      let model = embeddingModel
      let dimensions = store.selectedEmbeddingDimension
      indexTask = Task {
        defer {
          if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
          // The bounded read happens off the MainActor and security-scoped
          // access remains active until the read (and subsequent index) ends.
          let source = try await GroundingSourceImporter.importFileAsync(at: url)
          try Task.checkCancellation()
          guard importOperationID == operationID else { return }
          _ = await store.index(
            source,
            embeddingModel: model,
            dimensions: dimensions
          )
        } catch is CancellationError {
          // Replacing an import or closing the inspector is an intentional
          // cancellation; do not overwrite a newer import's diagnostics.
        } catch {
          guard importOperationID == operationID else { return }
          importError = error.localizedDescription
        }
      }
    }
  }

  private func copyToClipboard(_ text: String) {
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
}

nonisolated enum GroundingInspectorFormatting {
  static func score(_ value: Double) -> String {
    String(format: "%.4f", value)
  }

  static func location(_ provenance: GroundingProvenance) -> String {
    if let page = provenance.page {
      return "Page \(page) · chunk ordinal \(provenance.ordinal)"
    }
    return "Chunk ordinal \(provenance.ordinal)"
  }
}
