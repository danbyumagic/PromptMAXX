import CryptoKit
import Foundation

nonisolated public enum TraceKind: String, Codable, Hashable, Sendable {
  case refinement, comparisonCandidate, evaluationCase
}
nonisolated public enum TraceStage: String, Codable, Hashable, Sendable {
  case prepare, generate, validate, compile, evaluate
}

nonisolated public struct TraceStageEvent: Codable, Hashable, Sendable {
  public let stage: TraceStage
  public let startedAt: Date
  public let finishedAt: Date?
  public let summary: String
  public init(stage: TraceStage, startedAt: Date, finishedAt: Date? = nil, summary: String) {
    self.stage = stage
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.summary = summary
  }
}

nonisolated public struct RunTrace: Codable, Hashable, Sendable, Identifiable {
  public static let currentVersion = 1
  public static let redactionMarker = "[REDACTED]"
  public let run: RunRecord
  public let version: Int
  public let kind: TraceKind
  public let promptSpecID: UUID?
  public let revisionID: UUID?
  public let sourceText: String?
  public let renderedInput: String?
  public let compiledPrompt: String?
  public let provider: String
  public let endpointLabel: String
  public let generationOptions: PromptGenerationOptions
  public let validationIssueCount: Int
  public let retryCount: Int
  public let events: [TraceStageEvent]
  private let isRedacted: Bool
  public var isRedactedTrace: Bool { isRedacted }
  public let contentHash: String
  public let configurationHash: String
  public var id: UUID { run.id }
  public var model: String { run.model }
  public var profileID: String { run.profileID }
  public var status: RunStatus { run.status }
  public var startedAt: Date { run.startedAt }
  public var finishedAt: Date? { run.finishedAt }
  public var error: RunError? { run.error }
  public var cancellation: RunCancellation? { run.cancellation }
  public var metrics: RunMetrics { run.metrics }
  public var outputText: String? { run.output }

  public init(
    run: RunRecord, version: Int = 1, kind: TraceKind, promptSpecID: UUID? = nil,
    revisionID: UUID? = nil, sourceText: String? = nil, renderedInput: String? = nil,
    compiledPrompt: String? = nil, provider: String, endpointLabel: String,
    generationOptions: PromptGenerationOptions = .init(), validationIssueCount: Int = 0,
    retryCount: Int = 0, events: [TraceStageEvent] = []
  ) {
    self.run = run
    self.version = version
    self.kind = kind
    self.promptSpecID = promptSpecID
    self.revisionID = revisionID
    self.sourceText = sourceText
    self.renderedInput = renderedInput
    self.compiledPrompt = compiledPrompt
    self.provider = provider
    self.endpointLabel = endpointLabel
    self.generationOptions = generationOptions
    self.validationIssueCount = validationIssueCount
    self.retryCount = retryCount
    self.events = events
    self.isRedacted = false
    self.contentHash = Self.contentHash(sourceText, renderedInput, compiledPrompt, run.output)
    self.configurationHash = Self.configurationHash(run, provider, endpointLabel, generationOptions)
  }

  private init(
    run: RunRecord, version: Int, kind: TraceKind, promptSpecID: UUID?, revisionID: UUID?,
    sourceText: String?, renderedInput: String?, compiledPrompt: String?, provider: String,
    endpointLabel: String, generationOptions: PromptGenerationOptions, validationIssueCount: Int,
    retryCount: Int, events: [TraceStageEvent], isRedacted: Bool, contentHash: String,
    configurationHash: String
  ) {
    self.run = run
    self.version = version
    self.kind = kind
    self.promptSpecID = promptSpecID
    self.revisionID = revisionID
    self.sourceText = sourceText
    self.renderedInput = renderedInput
    self.compiledPrompt = compiledPrompt
    self.provider = provider
    self.endpointLabel = endpointLabel
    self.generationOptions = generationOptions
    self.validationIssueCount = validationIssueCount
    self.retryCount = retryCount
    self.events = events
    self.isRedacted = isRedacted
    self.contentHash = contentHash
    self.configurationHash = configurationHash
  }

  public var isConsistent: Bool { validationIssues.isEmpty }
  public var validationIssues: [String] {
    var issues: [String] = []
    if version != Self.currentVersion { issues.append("unsupported version") }
    if !run.isConsistent { issues.append("run inconsistent") }
    if provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || endpointLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      issues.append("provider and endpoint required")
    }
    if !generationOptions.isValid || validationIssueCount < 0 || retryCount < 0 {
      issues.append("invalid configuration counters")
    }
    if isRedacted {
      if sourceText != nil || renderedInput != nil || compiledPrompt != nil || run.output != nil {
        issues.append("redacted trace contains prompt content")
      }
      if let error, error.message != Self.redactionMarker {
        issues.append("redacted error contains message content")
      }
      if events.contains(where: { $0.summary != Self.redactionMarker }) {
        issues.append("redacted event contains summary content")
      }
    }
    let contentHashIsValid = Self.validHash(contentHash)
    if !contentHashIsValid {
      issues.append("content hash invalid")
    }
    if !Self.validHash(configurationHash)
      || configurationHash
        != Self.configurationHash(run, provider, endpointLabel, generationOptions)
    {
      issues.append("configuration hash invalid")
    }
    if !isRedacted && contentHashIsValid
      && contentHash != Self.contentHash(sourceText, renderedInput, compiledPrompt, run.output) {
      issues.append("content hash invalid")
    }
    var prior = run.startedAt
    for event in events {
      if event.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || event.startedAt < run.startedAt
        || event.startedAt < prior
        || event.finishedAt.map({ $0 < event.startedAt }) == true
        || event.finishedAt.map({ $0 < run.startedAt }) == true
        || event.startedAt > (run.finishedAt ?? Date.distantFuture)
        || event.finishedAt.map({ $0 > (run.finishedAt ?? Date.distantFuture) }) == true
        || event.finishedAt.map({
          $0 < prior
        }) == true
      {
        issues.append("stage events invalid")
      }
      prior = event.finishedAt ?? event.startedAt
    }
    if run.status.isTerminal, events.last?.finishedAt == nil, !events.isEmpty {
      issues.append("terminal trace needs a finished terminal event")
    }
    return issues
  }
  public func redacted() -> RunTrace {
    let redactedError = error.map {
      RunError(domain: $0.domain, code: $0.code, message: Self.redactionMarker)
    }
    let redactedRun = RunRecord(
      id: run.id, model: run.model, modelVersion: run.modelVersion, profileID: run.profileID,
      profileVersion: run.profileVersion, schemaVersion: run.schemaVersion,
      endpointLocality: run.endpointLocality, startedAt: run.startedAt, finishedAt: run.finishedAt,
      status: run.status, metrics: run.metrics, output: nil, error: redactedError,
      cancellation: run.cancellation)
    let redactedEvents = events.map {
      TraceStageEvent(
        stage: $0.stage, startedAt: $0.startedAt, finishedAt: $0.finishedAt,
        summary: Self.redactionMarker)
    }
    return RunTrace(
      run: redactedRun, version: version, kind: kind, promptSpecID: promptSpecID,
      revisionID: revisionID, sourceText: nil, renderedInput: nil, compiledPrompt: nil,
      provider: provider, endpointLabel: endpointLabel, generationOptions: generationOptions,
      validationIssueCount: validationIssueCount, retryCount: retryCount, events: redactedEvents,
      isRedacted: true, contentHash: contentHash, configurationHash: configurationHash)
  }
  public func jsonData(redacted: Bool = false) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(redacted ? self.redacted() : self)
  }
  public func markdown(redacted: Bool = false) -> String {
    let value = redacted ? self.redacted() : self
    return
      "# Run Trace\n\n- Redacted: \(value.isRedacted)\n- Kind: `\(value.kind.rawValue)`\n- Status: `\(value.status.rawValue)`\n- Model: `\(value.model)`\n- Content hash: `\(value.contentHash)`\n- Configuration hash: `\(value.configurationHash)`\n"
  }
  private struct ContentPayload: Codable {
    let source: String?
    let rendered: String?
    let compiled: String?
    let output: String?
  }
  private struct ConfigPayload: Codable {
    let provider: String
    let model: String
    let modelVersion: String?
    let profile: String
    let profileVersion: Int
    let schemaVersion: Int
    let endpoint: String
    let locality: EndpointLocality
    let options: PromptGenerationOptions
  }
  private static func digest<T: Codable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return String(repeating: "0", count: 64) }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }
      .joined()
  }
  private static func contentHash(
    _ source: String?, _ rendered: String?, _ compiled: String?, _ output: String?
  ) -> String {
    digest(ContentPayload(source: source, rendered: rendered, compiled: compiled, output: output))
  }
  private static func configurationHash(
    _ run: RunRecord, _ provider: String, _ endpoint: String, _ options: PromptGenerationOptions
  ) -> String {
    digest(
      ConfigPayload(
        provider: provider, model: run.model, modelVersion: run.modelVersion, profile: run.profileID,
        profileVersion: run.profileVersion, schemaVersion: run.schemaVersion, endpoint: endpoint,
        locality: run.endpointLocality, options: options))
  }
  private static func validHash(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
  }
}
