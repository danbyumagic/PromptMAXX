import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A factual browser for persisted traces. It does not rank runs or infer quality.
public struct TraceBrowserView: View {
  public let store: TraceStore
  @Environment(\.dismiss) private var dismiss

  @State private var query = ""
  @State private var kindFilter = ""
  @State private var statusFilter = ""
  @State private var modelFilter = ""
  @State private var selectedID: UUID?
  @State private var revealPrivateData = false
  @State private var confirmDelete = false
  @State private var confirmRetention = false
  @State private var showRetention = false
  @State private var retentionDate = Date().addingTimeInterval(-30 * 24 * 60 * 60)
  @State private var retentionFeedback: String?
  @State private var exportError: String?
  @State private var isExporting = false

  private let kinds: [TraceKind] = [.refinement, .comparisonCandidate, .evaluationCase]
  private let statuses: [RunStatus] = [.running, .completed, .failed, .cancelled]

  public init(store: TraceStore) {
    self.store = store
  }

  private var filteredTraces: [RunTrace] {
    store.filteredTraces(
      query: query,
      kind: TraceKind(rawValue: kindFilter),
      status: RunStatus(rawValue: statusFilter),
      model: modelFilter.isEmpty ? nil : modelFilter)
  }

  private var selectedTrace: RunTrace? {
    guard let selectedID else { return nil }
    return store.traces.first { $0.id == selectedID }
  }

  public var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
    } detail: {
      detail
    }
    .navigationTitle("Run Traces")
    .searchable(text: $query, placement: .sidebar, prompt: "Search traces")
    .task { await store.loadIfNeeded() }
    .onChange(of: store.traces) { _, traces in
      if let selectedID, !traces.contains(where: { $0.id == selectedID }) {
        self.selectedID = nil
      }
    }
    .alert("Delete trace?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) {
        guard let selectedID else { return }
        Task { await store.delete(id: selectedID) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes the selected trace from the local repository. It cannot be undone here.")
    }
    .alert("Retain traces?", isPresented: $confirmRetention) {
      Button("Retain", role: .destructive) {
        Task { @MainActor in
          let retained = await store.retain(from: retentionDate)
          retentionFeedback = retained
            ? "Retention completed. Traces outside the selected range were removed."
            : "Retention failed: \(store.error?.localizedDescription ?? "Unknown error")"
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Traces started before \(retentionDate.formatted(date: .abbreviated, time: .shortened)) will be removed from the local repository. This cannot be undone here.")
    }
    .sheet(isPresented: $showRetention) {
      retentionSheet
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let retentionFeedback {
        feedbackBanner(retentionFeedback, color: retentionFeedback.hasPrefix("Retention completed") ? .green : .red)
      }
      if let error = store.error, store.state == .ready {
        feedbackBanner("Last operation: \(error.localizedDescription)", color: .orange)
      }
      filterControls
      Divider()
      if store.isLoading {
        VStack(spacing: 10) {
          ProgressView()
          Text("Loading traces…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading traces")
      } else if let error = store.error, store.state == .failed {
        ContentUnavailableView {
          Label("Trace store unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
          Text(error.localizedDescription)
        } actions: {
          Button("Retry") { Task { await store.retry() } }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityElement(children: .combine)
      } else if filteredTraces.isEmpty {
        ContentUnavailableView(
          query.isEmpty ? "No traces yet" : "No matching traces",
          systemImage: query.isEmpty ? "clock.badge.questionmark" : "magnifyingglass",
          description: Text(query.isEmpty ? "Completed, failed, and cancelled runs appear here when the shared store receives them." : "Try a different search or clear the filters.")
        )
      } else {
        List(filteredTraces, selection: $selectedID) { trace in
          traceRow(trace)
            .tag(trace.id)
        }
        .listStyle(.sidebar)
      }
    }
    .padding(.vertical, 8)
    .toolbar { toolbarContent }
  }

  private var filterControls: some View {
    VStack(alignment: .leading, spacing: 7) {
      Picker("Kind", selection: $kindFilter) {
        Text("All kinds").tag("")
        ForEach(kinds, id: \.rawValue) { kind in
          Text(kind.rawValue).tag(kind.rawValue)
        }
      }
      Picker("Status", selection: $statusFilter) {
        Text("All statuses").tag("")
        ForEach(statuses, id: \.rawValue) { status in
          Text(status.rawValue.capitalized).tag(status.rawValue)
        }
      }
      Picker("Model", selection: $modelFilter) {
        Text("All models").tag("")
        ForEach(Array(Set(store.traces.map(\.model))).sorted(), id: \.self) { model in
          Text(model).tag(model)
        }
      }
      .accessibilityLabel("Filter by model")
    }
    .padding(.horizontal, 10)
  }

  private func traceRow(_ trace: RunTrace) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: statusSymbol(trace.status))
          .foregroundStyle(statusColor(trace.status))
        Text(trace.model)
          .font(.headline)
          .lineLimit(1)
        Spacer()
        Text(trace.startedAt, style: .relative)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Text("\(trace.kind.rawValue) · \(trace.status.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(trace.profileID)
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(trace.model), \(trace.kind.rawValue), \(trace.status.rawValue), profile \(trace.profileID)")
  }

  @ViewBuilder
  private var detail: some View {
    if let selectedTrace {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          privacyNotice
          if let exportError {
            Label("Export failed: \(exportError)", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .textSelection(.enabled)
              .accessibilityLabel("Export failed: \(exportError)")
          }
          traceHeader(selectedTrace)
          configuration(selectedTrace)
          lifecycle(selectedTrace)
          content(selectedTrace)
          events(selectedTrace)
        }
        .padding(22)
      }
      .toolbar { detailToolbar }
    } else if store.isLoading {
      ProgressView("Loading traces…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ContentUnavailableView(
        "Select a trace",
        systemImage: "doc.text.magnifyingglass",
        description: Text("Choose a run from the sidebar to inspect its factual configuration and evidence.")
      )
    }
  }

  private var privacyNotice: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        Label("Privacy review", systemImage: "lock.shield")
          .font(.headline)
        Text("Traces can contain source prompts, rendered inputs, compiled prompts, and model output. Exports are redacted by default.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Toggle("Reveal prompt, output, errors, and event summaries", isOn: $revealPrivateData)
          .accessibilityHint("When enabled, the screen and exported files include unredacted prompt, output, error, and event content.")
        Text(revealPrivateData ? "Reveal is on: the screen and exported files will include content." : "Reveal is off: the screen hides content and exports redact prompt, output, error, and event content.")
          .font(.caption)
          .foregroundStyle(revealPrivateData ? .orange : .secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func traceHeader(_ trace: RunTrace) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 5) {
        Text(trace.model)
          .font(.title2.bold())
        Text("\(trace.kind.rawValue) · \(trace.status.rawValue)")
          .font(.subheadline)
          .foregroundStyle(statusColor(trace.status))
        Text(trace.id.uuidString)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
      }
      Spacer()
    }
  }

  private func configuration(_ trace: RunTrace) -> some View {
    GroupBox("Configuration") {
      VStack(alignment: .leading, spacing: 7) {
        fact("Provider", trace.provider)
        fact("Model version", trace.run.modelVersion ?? "Not recorded")
        fact("Profile", "\(trace.profileID) v\(trace.run.profileVersion)")
        fact("Schema", "v\(trace.run.schemaVersion)")
        fact("Endpoint", "\(trace.endpointLabel) · \(trace.run.endpointLocality.rawValue)")
        fact("Options", "temperature \(String(format: "%.2f", trace.generationOptions.temperature)) · top-p \(String(format: "%.2f", trace.generationOptions.topP)) · max \(trace.generationOptions.maxTokens) · stream \(trace.generationOptions.stream ? "yes" : "no")")
        fact("Content hash", trace.contentHash)
        fact("Configuration hash", trace.configurationHash)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func lifecycle(_ trace: RunTrace) -> some View {
    GroupBox("Lifecycle and measurements") {
      VStack(alignment: .leading, spacing: 7) {
        fact("Started", trace.startedAt.formatted(date: .abbreviated, time: .standard))
        fact("Finished", trace.finishedAt?.formatted(date: .abbreviated, time: .standard) ?? "Still running")
        fact("TTFT", trace.metrics.ttftMilliseconds.map { String(format: "%.1f ms", $0) } ?? "Not recorded")
        fact("Duration", trace.metrics.totalDurationMilliseconds.map { String(format: "%.1f ms", $0) } ?? "Not recorded")
        fact("Tokens", "\(trace.metrics.inputTokenCount.map(String.init) ?? "—") in · \(trace.metrics.outputTokenCount.map(String.init) ?? "—") out")
        fact("Retries", "\(trace.retryCount)")
        fact("Validation issues", "\(trace.validationIssueCount)")
        if let cancellation = trace.cancellation {
          fact("Cancellation", "\(cancellation.reason.rawValue) at \(cancellation.requestedAt.formatted(date: .abbreviated, time: .standard))")
        }
        if let error = trace.error {
          fact("Error", revealPrivateData ? error.message : RunTrace.redactionMarker)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func content(_ trace: RunTrace) -> some View {
    GroupBox("Prompt and output") {
      VStack(alignment: .leading, spacing: 10) {
        if revealPrivateData {
          contentBlock("Source", trace.sourceText)
          contentBlock("Rendered input", trace.renderedInput)
          contentBlock("Compiled prompt", trace.compiledPrompt)
          contentBlock("Model output", trace.outputText)
        } else {
          Text("Content is hidden. Turn on Reveal prompt and output content to inspect it.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func events(_ trace: RunTrace) -> some View {
    GroupBox("Stage events") {
      if trace.events.isEmpty {
        Text("No stage events recorded.")
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 7) {
          ForEach(Array(trace.events.enumerated()), id: \.offset) { index, event in
            HStack(alignment: .top, spacing: 8) {
              Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
              VStack(alignment: .leading, spacing: 2) {
                Text(event.stage.rawValue.capitalized)
                  .font(.caption.weight(.semibold))
                Text(revealPrivateData ? event.summary : RunTrace.redactionMarker)
                  .font(.caption)
                Text("\(event.startedAt.formatted(date: .omitted, time: .standard)) → \(event.finishedAt?.formatted(date: .omitted, time: .standard) ?? "open")")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
  }

  private func contentBlock(_ title: String, _ value: String?) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title.uppercased())
        .font(.caption2)
        .foregroundStyle(.tertiary)
      Text(value ?? "Not recorded")
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
  }

  private func fact(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.caption.weight(.semibold))
        .frame(width: 145, alignment: .leading)
      Text(value)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }

  private func feedbackBanner(_ message: String, color: Color) -> some View {
    let icon = message.hasPrefix("Retention failed") || message.hasPrefix("Last operation")
      ? "exclamationmark.triangle" : "info.circle"
    return Label(message, systemImage: icon)
      .font(.caption)
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(message)
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup {
      Button { Task { await store.retry() } } label: {
        Label("Refresh traces", systemImage: "arrow.clockwise")
      }
      .disabled(store.isBusy)
      Button { showRetention = true } label: {
        Label("Retain traces", systemImage: "calendar.badge.clock")
      }
      .disabled(store.isBusy || store.traces.isEmpty)
    }
    ToolbarItem(placement: .cancellationAction) {
      Button("Close") { dismiss() }
        .accessibilityLabel("Close trace browser")
    }
  }

  @ToolbarContentBuilder
  private var detailToolbar: some ToolbarContent {
    ToolbarItemGroup {
      Menu {
        Button("Export JSON") { exportJSON() }
        Button("Export Markdown") { exportMarkdown() }
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .disabled(isExporting || store.isBusy)
      Button(role: .destructive) { confirmDelete = true } label: {
        Label("Delete trace", systemImage: "trash")
      }
      .disabled(store.isBusy)
    }
  }

  private var retentionSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Retain traces")
        .font(.title2.bold())
      Text("Traces started before this date will be removed from the local repository. This is irreversible here.")
        .foregroundStyle(.secondary)
      DatePicker("Keep traces from", selection: $retentionDate, displayedComponents: [.date, .hourAndMinute])
      HStack {
        Button("Cancel") { showRetention = false }
          .buttonStyle(.borderless)
        Spacer()
        Button("Retain") {
          showRetention = false
          confirmRetention = true
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 420)
  }

  private func exportJSON() {
    exportError = nil
    isExporting = true
    let redacted = !revealPrivateData
    Task { @MainActor in
      defer { isExporting = false }
      do {
        let data = try await store.exportJSON(redacted: redacted)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = filename(fileExtension: "json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
      } catch {
        exportError = error.localizedDescription
      }
    }
  }

  private func exportMarkdown() {
    exportError = nil
    isExporting = true
    let redacted = !revealPrivateData
    Task { @MainActor in
      defer { isExporting = false }
      do {
        let markdown = try await store.exportMarkdown(redacted: redacted)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = filename(fileExtension: "md")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try Data(markdown.utf8).write(to: url, options: .atomic)
      } catch {
        exportError = error.localizedDescription
      }
    }
  }

  private func filename(fileExtension: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "promptmaxx-traces-\(formatter.string(from: Date())).\(fileExtension)"
  }

  private func statusSymbol(_ status: RunStatus) -> String {
    switch status {
    case .running: return "hourglass"
    case .completed: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    case .cancelled: return "stop.circle.fill"
    }
  }

  private func statusColor(_ status: RunStatus) -> Color {
    switch status {
    case .running: return .orange
    case .completed: return .green
    case .failed: return .red
    case .cancelled: return .secondary
    }
  }
}
