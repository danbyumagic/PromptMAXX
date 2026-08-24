import Foundation

nonisolated public enum RunTraceFactory {
  public static func refinement(
    result: PromptSpecGenerationResult, sourceText: String, profile: PromptProfile,
    endpointLabel: String, endpointLocality: EndpointLocality, modelVersion: String? = nil,
    revisionID: UUID? = nil, runID: UUID? = nil, provider: String = "Ollama"
  ) throws -> RunTrace {
    guard result.profileID == profile.id else {
      throw RunTraceFactoryError.invalidResult("Refinement profile does not match the result.")
    }
    guard (1...2).contains(result.attemptCount) else {
      throw RunTraceFactoryError.invalidResult("Refinement attempt count must be one or two.")
    }
    guard !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !endpointLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      result.finishedAt >= result.startedAt
    else { throw RunTraceFactoryError.invalidResult("Refinement trace inputs are invalid.") }
    let run = RunRecord(
      id: runID ?? UUID(),
      model: result.model, modelVersion: modelVersion, profileID: result.profileID,
      profileVersion: profile.version, schemaVersion: result.spec.schemaVersion,
      endpointLocality: endpointLocality, startedAt: result.startedAt,
      finishedAt: result.finishedAt, status: .completed, metrics: result.metrics,
      output: result.rawResponse)
    let events = [
      TraceStageEvent(
        stage: .generate, startedAt: result.startedAt, finishedAt: result.finishedAt,
        summary: "Completed refinement generation")
    ]
    let trace = RunTrace(
      run: run, kind: .refinement, promptSpecID: result.spec.id, revisionID: revisionID,
      sourceText: sourceText, renderedInput: nil, compiledPrompt: result.compiledPrompt,
      provider: provider, endpointLabel: endpointLabel,
      generationOptions: profile.generationOptions, validationIssueCount: 0,
      retryCount: result.attemptCount - 1, events: events)
    guard trace.isConsistent else {
      throw RunTraceFactoryError.invalidResult("Refinement trace is inconsistent.")
    }
    return trace
  }

  /// Builds a factual failed refinement trace. The caller supplies the run
  /// identity and timestamps captured at execution boundaries; this factory
  /// never invents output, retries, or timing metadata.
  public static func refinementFailed(
    runID: UUID, startedAt: Date, finishedAt: Date, model: String,
    profile: PromptProfile, sourceText: String, endpointLabel: String,
    endpointLocality: EndpointLocality, error: RunError, modelVersion: String? = nil,
    revisionID: UUID? = nil, provider: String = "Ollama"
  ) throws -> RunTrace {
    try refinementTerminal(
      runID: runID, startedAt: startedAt, finishedAt: finishedAt, model: model,
      profile: profile, sourceText: sourceText, endpointLabel: endpointLabel,
      endpointLocality: endpointLocality, status: .failed, error: error,
      cancellation: nil, modelVersion: modelVersion, revisionID: revisionID,
      provider: provider, summary: "Failed refinement generation")
  }

  /// Builds a factual cancelled refinement trace. A cancelled run has no
  /// output and no fabricated retry count or model metrics.
  public static func refinementCancelled(
    runID: UUID, startedAt: Date, finishedAt: Date, model: String,
    profile: PromptProfile, sourceText: String, endpointLabel: String,
    endpointLocality: EndpointLocality, reason: RunCancellationReason,
    modelVersion: String? = nil, revisionID: UUID? = nil, provider: String = "Ollama"
  ) throws -> RunTrace {
    try refinementTerminal(
      runID: runID, startedAt: startedAt, finishedAt: finishedAt, model: model,
      profile: profile, sourceText: sourceText, endpointLabel: endpointLabel,
      endpointLocality: endpointLocality, status: .cancelled, error: nil,
      cancellation: RunCancellation(reason: reason, requestedAt: finishedAt),
      modelVersion: modelVersion, revisionID: revisionID, provider: provider,
      summary: "Cancelled refinement generation")
  }

  public static func comparison(
    result: PromptCandidateResult, sourceText: String, endpointLabel: String,
    endpointLocality: EndpointLocality, provider: String = "Ollama"
  ) throws -> RunTrace? {
    guard result.status != .pending, result.status != .running else { return nil }
    guard let started = result.startedAt, let finished = result.finishedAt else {
      // A cancelled candidate with no start timestamp never executed and is
      // intentionally omitted from factual traces.
      if result.status == .cancelled { return nil }
      throw RunTraceFactoryError.missingTiming
    }
    guard finished >= started else {
      throw RunTraceFactoryError.invalidResult("Finished time precedes start")
    }
    guard result.status != .failed || result.error != nil else {
      throw RunTraceFactoryError.invalidResult("Failed result requires an error")
    }
    let status: RunStatus =
      result.status == .completed
      ? .completed : (result.status == .cancelled ? .cancelled : .failed)
    let run = RunRecord(
      model: result.candidate.model, profileID: result.candidate.profile.id,
      profileVersion: result.candidate.profile.version,
      schemaVersion: result.spec?.schemaVersion ?? PromptSpec.currentSchemaVersion,
      endpointLocality: endpointLocality, startedAt: started, finishedAt: finished, status: status,
      metrics: result.metrics, output: nil, error: status == .failed ? result.error : nil,
      cancellation: status == .cancelled
        ? RunCancellation(reason: .unknown, requestedAt: finished) : nil)
    let trace = RunTrace(
      run: run, kind: .comparisonCandidate, promptSpecID: result.spec?.id, sourceText: sourceText,
      renderedInput: sourceText, compiledPrompt: result.compiledPrompt, provider: provider,
      endpointLabel: endpointLabel, generationOptions: result.candidate.profile.generationOptions,
      validationIssueCount: result.validationFailure == nil ? 0 : 1,
      retryCount: max(0, result.attempts - 1),
      events: [
        TraceStageEvent(
          stage: .generate, startedAt: started, finishedAt: finished,
          summary: result.status == .completed
            ? "Completed candidate run"
            : (result.status == .cancelled ? "Cancelled candidate run" : "Failed candidate run"))
      ])
    guard trace.isConsistent else {
      throw RunTraceFactoryError.invalidResult("Comparison trace is inconsistent.")
    }
    return trace
  }

  /// Constructs a complete comparison batch before the caller persists it.
  /// A malformed terminal candidate throws, so callers cannot accidentally
  /// append only the valid prefix of a comparison run.
  public static func comparisonBatch(
    result: PromptComparisonResult, endpointLabel: String,
    endpointLocality: EndpointLocality, provider: String = "Ollama"
  ) throws -> [RunTrace] {
    try result.candidates.compactMap { candidate in
      try comparison(
        result: candidate,
        sourceText: result.sourceText,
        endpointLabel: endpointLabel,
        endpointLocality: endpointLocality,
        provider: provider
      )
    }
  }

  private static func refinementTerminal(
    runID: UUID, startedAt: Date, finishedAt: Date, model: String,
    profile: PromptProfile, sourceText: String, endpointLabel: String,
    endpointLocality: EndpointLocality, status: RunStatus, error: RunError?,
    cancellation: RunCancellation?, modelVersion: String?, revisionID: UUID?, provider: String,
    summary: String
  ) throws -> RunTrace {
    guard !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !endpointLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      finishedAt >= startedAt,
      profile.validationIssues.isEmpty
    else { throw RunTraceFactoryError.invalidResult("Refinement trace inputs are invalid.") }

    let run = RunRecord(
      id: runID, model: model, modelVersion: modelVersion, profileID: profile.id,
      profileVersion: profile.version, schemaVersion: PromptSpec.currentSchemaVersion,
      endpointLocality: endpointLocality, startedAt: startedAt, finishedAt: finishedAt,
      status: status, metrics: .init(), output: nil, error: error, cancellation: cancellation)
    let trace = RunTrace(
      run: run, kind: .refinement, revisionID: revisionID, sourceText: sourceText,
      compiledPrompt: nil, provider: provider, endpointLabel: endpointLabel,
      generationOptions: profile.generationOptions, validationIssueCount: 0, retryCount: 0,
      events: [TraceStageEvent(stage: .generate, startedAt: startedAt, finishedAt: finishedAt, summary: summary)])
    guard trace.isConsistent else {
      throw RunTraceFactoryError.invalidResult("Refinement trace is inconsistent.")
    }
    return trace
  }

  public static func evaluation(
    result: EvalCaseResult, suite: EvalSuite, candidate: EvalCandidateConfiguration,
    endpointLabel: String, endpointLocality: EndpointLocality, provider: String = "Ollama"
  ) throws -> RunTrace {
    guard let evalCase = suite.cases.first(where: { $0.id == result.caseID }),
      evalCase.version == result.suiteCaseVersion, candidate.id == result.candidateID,
      candidate.version == result.candidateVersion, candidate.model == result.model
    else { throw RunTraceFactoryError.mismatchedEvaluation }
    guard let startedAt = result.startedAt, let finishedAt = result.finishedAt else {
      throw RunTraceFactoryError.missingTiming
    }
    guard finishedAt >= startedAt else {
      throw RunTraceFactoryError.invalidResult("Finished time precedes start")
    }
    let started = startedAt
    let finished = finishedAt
    let status: RunStatus = result.error == nil ? .completed : .failed
    let run = RunRecord(
      model: candidate.model, profileID: candidate.id, profileVersion: candidate.version,
      schemaVersion: suite.version, endpointLocality: endpointLocality, startedAt: started,
      finishedAt: finished, status: status,
      metrics: RunMetrics(
        ttftMilliseconds: nil, totalDurationMilliseconds: result.latencyMilliseconds,
        inputTokenCount: result.inputTokenCount, outputTokenCount: result.outputTokenCount),
      output: result.output, error: result.error.map { RunError(message: $0) })
    let trace = RunTrace(
      run: run, kind: .evaluationCase, revisionID: nil, sourceText: evalCase.input,
      renderedInput: nil, compiledPrompt: nil, provider: provider,
      endpointLabel: endpointLabel, generationOptions: candidate.generationOptions,
      validationIssueCount: result.checkResults.filter { !$0.passed }.count,
      events: [
        TraceStageEvent(
          stage: .evaluate, startedAt: started, finishedAt: finished,
          summary: result.error == nil ? "Completed evaluation case" : "Failed evaluation case")
      ])
    guard trace.isConsistent else {
      throw RunTraceFactoryError.invalidResult("Evaluation trace is inconsistent.")
    }
    return trace
  }
}

nonisolated public enum RunTraceFactoryError: Error, LocalizedError, Hashable, Sendable {
  case missingTiming
  case mismatchedEvaluation
  case invalidResult(String)
  public var errorDescription: String? {
    switch self {
    case .missingTiming: return "Trace timing is unavailable."
    case .mismatchedEvaluation: return "Evaluation result does not match suite or candidate."
    case .invalidResult(let message): return message
    }
  }
}
