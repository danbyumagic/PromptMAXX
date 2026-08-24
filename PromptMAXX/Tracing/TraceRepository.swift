import Foundation

nonisolated public struct TraceEnvelope: Codable, Hashable, Sendable {
  public static let currentVersion = 1
  public let version: Int
  public var traces: [RunTrace]

  public init(version: Int = TraceEnvelope.currentVersion, traces: [RunTrace] = []) {
    self.version = version
    self.traces = traces
  }
}

/// An actor-isolated, versioned JSON store for immutable run traces.
public actor TraceRepository {
  private let url: URL
  private let fileManager: FileManager

  /// Directory creation is deferred to the first mutation so failures are
  /// reported through `TraceRepositoryError` instead of being swallowed.
  public init(fileURL: URL, fileManager: FileManager = .default) {
    self.url = fileURL
    self.fileManager = fileManager
  }

  public init(fileManager: FileManager = .default) throws {
    try self.init(fileURL: Self.defaultFileURL(fileManager: fileManager), fileManager: fileManager)
  }

  public static func defaultFileURL(
    applicationName: String = "PromptMAXX", fileManager: FileManager = .default
  ) throws -> URL {
    guard !applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      throw TraceRepositoryError.invalidFileURL
    }
    return base.appendingPathComponent(applicationName, isDirectory: true)
      .appendingPathComponent("traces.json", isDirectory: false)
  }

  public func load() throws -> [RunTrace] {
    guard fileManager.fileExists(atPath: url.path) else { return [] }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw TraceRepositoryError.readFailed(url, reason: error.localizedDescription)
    }

    let envelope: TraceEnvelope
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      envelope = try decoder.decode(TraceEnvelope.self, from: data)
    } catch {
      throw TraceRepositoryError.corrupt(url, reason: error.localizedDescription)
    }

    try validate(envelope)
    return envelope.traces
  }

  public func append(_ trace: RunTrace) throws {
    try append(contentsOf: [trace])
  }

  /// Validates and appends a batch as one actor transaction and one atomic write.
  public func append(contentsOf newTraces: [RunTrace]) throws {
    guard !newTraces.isEmpty else { return }
    for trace in newTraces {
      guard trace.isConsistent else {
        throw TraceRepositoryError.invalidTrace(trace.validationIssues)
      }
    }
    var batchIDs = Set<UUID>()
    for trace in newTraces {
      guard batchIDs.insert(trace.id).inserted else {
        throw TraceRepositoryError.duplicateTraceID(trace.id)
      }
    }

    var traces = try load()
    guard !traces.contains(where: { batchIDs.contains($0.id) }) else {
      let duplicate = traces.first(where: { batchIDs.contains($0.id) })?.id
      if let duplicate { throw TraceRepositoryError.duplicateTraceID(duplicate) }
      throw TraceRepositoryError.invalidEnvelope(url, issues: ["Duplicate trace ID"])
    }
    traces.append(contentsOf: newTraces)
    try write(TraceEnvelope(traces: traces))
  }

  public func delete(id: UUID) throws {
    var traces = try load()
    guard let index = traces.firstIndex(where: { $0.id == id }) else {
      throw TraceRepositoryError.notFound(url, id: id)
    }
    traces.remove(at: index)
    try write(TraceEnvelope(traces: traces))
  }

  /// Compatibility wrapper retaining the original lower-bound API.
  public func retain(since date: Date) throws {
    try retain(from: date, to: nil)
  }

  /// Retains traces whose start dates fall inside the inclusive range.
  public func retain(from: Date? = nil, to: Date? = nil) throws {
    try validateRange(from: from, to: to)
    let retained = try load().filter { trace in
      Self.isIncluded(trace.startedAt, from: from, to: to)
    }
    try write(TraceEnvelope(traces: retained))
  }

  /// Compatibility wrapper retaining the original lower-bound filter API.
  public func filter(
    kind: TraceKind? = nil, model: String? = nil, status: RunStatus? = nil, since: Date? = nil
  ) throws -> [RunTrace] {
    try filter(kind: kind, model: model, status: status, from: since, to: nil)
  }

  /// Filters by an inclusive start-date range when `from` and/or `to` are set.
  public func filter(
    kind: TraceKind? = nil, model: String? = nil, status: RunStatus? = nil,
    from: Date?, to: Date?
  ) throws -> [RunTrace] {
    try validateRange(from: from, to: to)
    return try load().filter { trace in
      (kind == nil || trace.kind == kind)
        && (model == nil || trace.model == model)
        && (status == nil || trace.status == status)
        && Self.isIncluded(trace.startedAt, from: from, to: to)
    }
  }

  public func exportJSON(redacted: Bool = false) throws -> Data {
    let traces = try load().map { redacted ? $0.redacted() : $0 }
    return try encode(TraceEnvelope(traces: traces))
  }

  public func exportMarkdown(redacted: Bool = false) throws -> String {
    let traces = try load().map { redacted ? $0.redacted() : $0 }
    var lines = [
      "# Trace Envelope",
      "",
      "- Version: `\(TraceEnvelope.currentVersion)`",
      "- Traces: \(traces.count)",
      "- Redacted: \(redacted)",
      ""
    ]
    for (index, trace) in traces.enumerated() {
      lines += ["## Trace \(index + 1): `\(trace.id.uuidString)`", "", markdown(for: trace), ""]
    }
    return lines.joined(separator: "\n")
  }

  private func markdown(for trace: RunTrace) -> String {
    func date(_ value: Date?) -> String {
      guard let value else { return "Not recorded" }
      return ISO8601DateFormatter().string(from: value)
    }
    func fenced(_ value: String) -> String {
      let escaped = value.replacingOccurrences(of: "```", with: "``\u{200B}`")
      return "```text\n\(escaped)\n```"
    }
    func content(_ value: String?) -> String {
      guard let value else { return trace.isRedactedTrace ? "[REDACTED]" : "Not recorded" }
      return fenced(value)
    }
    func optionalNumber<T>(_ value: T?) -> String {
      guard let value else { return "Not recorded" }
      return String(describing: value)
    }

    var lines = [
      "# Run Trace",
      "",
      "- ID: `\(trace.id.uuidString)`",
      "- Version: `\(trace.version)`",
      "- Kind: `\(trace.kind.rawValue)`",
      "- Redacted: `\(trace.isRedactedTrace)`",
      "- Prompt spec ID: `\(trace.promptSpecID?.uuidString ?? "Not recorded")`",
      "- Revision ID: `\(trace.revisionID?.uuidString ?? "Not recorded")`",
      "- Provider: `\(trace.provider)`",
      "- Model: `\(trace.model)`",
      "- Model version: `\(trace.run.modelVersion ?? "Not recorded")`",
      "- Profile: `\(trace.profileID)` (v\(trace.run.profileVersion))",
      "- Schema: `\(trace.run.schemaVersion)`",
      "- Endpoint: `\(trace.endpointLabel)` (\(trace.run.endpointLocality.rawValue))",
      "- Status: `\(trace.status.rawValue)`",
      "- Started: `\(date(trace.startedAt))`",
      "- Finished: `\(date(trace.finishedAt))`",
      "- TTFT milliseconds: `\(optionalNumber(trace.metrics.ttftMilliseconds))`",
      "- Total duration milliseconds: `\(optionalNumber(trace.metrics.totalDurationMilliseconds))`",
      "- Input tokens: `\(optionalNumber(trace.metrics.inputTokenCount))`",
      "- Output tokens: `\(optionalNumber(trace.metrics.outputTokenCount))`",
      "- Retries: `\(trace.retryCount)`",
      "- Validation issues: `\(trace.validationIssueCount)`",
      "- Content hash: `\(trace.contentHash)`",
      "- Configuration hash: `\(trace.configurationHash)`",
      "",
      "## Generation options",
      "",
      "- Temperature: `\(trace.generationOptions.temperature)`",
      "- Top-p: `\(trace.generationOptions.topP)`",
      "- Max tokens: `\(trace.generationOptions.maxTokens)`",
      "- Seed: `\(trace.generationOptions.seed.map(String.init) ?? "Not recorded")`",
      "- Stream: `\(trace.generationOptions.stream)`",
      "",
      "## Error and cancellation",
      ""
    ]
    if let error = trace.error {
      let domain = trace.isRedactedTrace ? "[REDACTED]" : (error.domain ?? "Not recorded")
      let code = trace.isRedactedTrace ? "[REDACTED]" : (error.code.map(String.init) ?? "Not recorded")
      lines += ["- Error domain: `\(domain)`", "- Error code: `\(code)`", "- Error message:", fenced(error.message)]
    } else {
      lines.append("- Error: Not recorded")
    }
    if let cancellation = trace.cancellation {
      lines += ["- Cancellation reason: `\(cancellation.reason.rawValue)`", "- Cancellation requested: `\(date(cancellation.requestedAt))`"]
    } else {
      lines.append("- Cancellation: Not recorded")
    }
    lines += ["", "## Stage events", ""]
    if trace.events.isEmpty {
      lines.append("- None recorded")
    } else {
      for (index, event) in trace.events.enumerated() {
        lines += [
          "### Event \(index + 1): \(event.stage.rawValue)",
          "",
          "- Started: `\(date(event.startedAt))`",
          "- Finished: `\(date(event.finishedAt))`",
          "- Summary:",
          fenced(event.summary),
          ""
        ]
      }
    }
    lines += [
      "## Prompt and output",
      "",
      "### Source",
      content(trace.sourceText),
      "",
      "### Rendered input",
      content(trace.renderedInput),
      "",
      "### Compiled prompt",
      content(trace.compiledPrompt),
      "",
      "### Model output",
      content(trace.outputText)
    ]
    return lines.joined(separator: "\n")
  }

  private func validate(_ envelope: TraceEnvelope) throws {
    guard envelope.version == TraceEnvelope.currentVersion else {
      throw TraceRepositoryError.unsupportedVersion(
        url, expected: TraceEnvelope.currentVersion, actual: envelope.version)
    }

    var seenIDs = Set<UUID>()
    var invalidIssues: [String] = []
    for trace in envelope.traces {
      guard seenIDs.insert(trace.id).inserted else {
        throw TraceRepositoryError.duplicateTraceID(trace.id)
      }
      if !trace.isConsistent {
        invalidIssues.append("\(trace.id.uuidString): \(trace.validationIssues.joined(separator: "; "))")
      }
    }
    if !invalidIssues.isEmpty {
      throw TraceRepositoryError.invalidEnvelope(url, issues: invalidIssues)
    }
  }

  private func validateRange(from: Date?, to: Date?) throws {
    if let from, let to, from > to {
      throw TraceRepositoryError.invalidDateRange(from: from, to: to)
    }
  }

  private static func isIncluded(_ date: Date, from: Date?, to: Date?) -> Bool {
    if let from, date < from { return false }
    if let to, date > to { return false }
    return true
  }

  private func encode(_ envelope: TraceEnvelope) throws -> Data {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      return try encoder.encode(envelope)
    } catch {
      throw TraceRepositoryError.encodingFailed(url, reason: error.localizedDescription)
    }
  }

  private func write(_ envelope: TraceEnvelope) throws {
    try validate(envelope)
    let data = try encode(envelope)
    let directory = url.deletingLastPathComponent()
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw TraceRepositoryError.directoryCreationFailed(
        directory, reason: error.localizedDescription)
    }
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw TraceRepositoryError.writeFailed(url, reason: error.localizedDescription)
    }
  }
}

nonisolated public enum TraceRepositoryError: Error, LocalizedError, Hashable, Sendable {
  case invalidFileURL
  case corrupt(URL, reason: String)
  case unsupportedVersion(URL, expected: Int, actual: Int)
  case invalidEnvelope(URL, issues: [String])
  case invalidTrace([String])
  case duplicateTraceID(UUID)
  case notFound(URL, id: UUID)
  case invalidDateRange(from: Date, to: Date)
  case directoryCreationFailed(URL, reason: String)
  case readFailed(URL, reason: String)
  case encodingFailed(URL, reason: String)
  case writeFailed(URL, reason: String)
  case unexpected(String)
  case busy

  public var isRecoverableOperationError: Bool {
    switch self {
    case .duplicateTraceID, .invalidTrace, .notFound, .invalidDateRange, .busy:
      return true
    case .invalidFileURL, .corrupt, .unsupportedVersion, .invalidEnvelope,
        .directoryCreationFailed, .readFailed, .encodingFailed, .writeFailed, .unexpected:
      return false
    }
  }

  public var errorDescription: String? {
    switch self {
    case .invalidFileURL:
      return "The trace repository URL is invalid."
    case let .corrupt(url, reason):
      return "Trace store at \(url.path) is corrupt: \(reason)"
    case let .unsupportedVersion(url, expected, actual):
      return "Trace store at \(url.path) uses version \(actual); expected version \(expected)."
    case let .invalidEnvelope(url, issues):
      return "Trace store at \(url.path) contains invalid traces: \(issues.joined(separator: "; "))"
    case let .invalidTrace(issues):
      return "Trace is invalid: \(issues.joined(separator: "; "))"
    case let .duplicateTraceID(id):
      return "Trace ID \(id.uuidString) already exists."
    case let .notFound(url, id):
      return "Trace ID \(id.uuidString) was not found in \(url.path)."
    case let .invalidDateRange(from, to):
      return "Trace date range is invalid: \(from) is after \(to)."
    case let .directoryCreationFailed(url, reason):
      return "Could not create trace directory at \(url.path): \(reason)"
    case let .readFailed(url, reason):
      return "Could not read trace store at \(url.path): \(reason)"
    case let .encodingFailed(url, reason):
      return "Could not encode trace store for \(url.path): \(reason)"
    case let .writeFailed(url, reason):
      return "Could not write trace store at \(url.path): \(reason)"
    case let .unexpected(reason):
      return "Unexpected trace repository failure: \(reason)"
    case .busy:
      return "The trace store is busy with another operation. Try again when it finishes."
    }
  }
}
