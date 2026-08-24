import XCTest

@testable import PromptMAXX

final class RunTraceFactoryTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 10)
  private var finish: Date { start.addingTimeInterval(1) }

  func testRefinementPreservesIdentityRetryAndVersions() throws {
    let spec = PromptSpec(
      title: "T", objective: "O", context: "", constraints: [], assumptions: [],
      missingQuestions: [], outputContract: "C", acceptanceCriteria: [])
    let result = PromptSpecGenerationResult(
      spec: spec, compiledPrompt: "compiled", rawResponse: "raw", attemptCount: 2,
      model: "model", profileID: PromptProfile.concise.id, startedAt: start,
      finishedAt: finish, metrics: RunMetrics(totalDurationMilliseconds: 1))
    let revisionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let runID = UUID()

    let trace = try RunTraceFactory.refinement(
      result: result, sourceText: "source", profile: .concise, endpointLabel: "loopback",
      endpointLocality: .local, modelVersion: "v1", revisionID: revisionID, runID: runID)

    XCTAssertEqual(trace.id, runID)
    XCTAssertEqual(trace.revisionID, revisionID)
    XCTAssertEqual(trace.run.modelVersion, "v1")
    XCTAssertEqual(trace.profileID, PromptProfile.concise.id)
    XCTAssertEqual(trace.retryCount, 1)
    XCTAssertEqual(trace.outputText, "raw")
    XCTAssertNil(trace.renderedInput)
    XCTAssertTrue(trace.isConsistent)
  }

  func testRefinementRejectsMismatchedProfileAndInvalidAttempts() {
    let spec = PromptSpec(
      title: "T", objective: "O", context: "", constraints: [], assumptions: [],
      missingQuestions: [], outputContract: "C", acceptanceCriteria: [])
    let result = PromptSpecGenerationResult(
      spec: spec, compiledPrompt: "compiled", rawResponse: "raw", attemptCount: 3,
      model: "model", profileID: "wrong", startedAt: start, finishedAt: finish,
      metrics: .init())
    XCTAssertThrowsError(
      try RunTraceFactory.refinement(
        result: result, sourceText: "source", profile: .concise, endpointLabel: "loopback",
        endpointLocality: .local))
  }

  func testRefinementFailureAndCancellationRetainFactualTerminalState() throws {
    let runID = UUID()
    let failure = try RunTraceFactory.refinementFailed(
      runID: runID, startedAt: start, finishedAt: finish, model: "model",
      profile: .concise, sourceText: "source", endpointLabel: "loopback",
      endpointLocality: .local, error: RunError(domain: "provider", code: 7, message: "offline"),
      modelVersion: "digest", revisionID: runID)
    XCTAssertEqual(failure.id, runID)
    XCTAssertEqual(failure.status, .failed)
    XCTAssertEqual(failure.error?.message, "offline")
    XCTAssertNil(failure.outputText)
    XCTAssertEqual(failure.retryCount, 0)
    XCTAssertTrue(failure.isConsistent)

    let cancelled = try RunTraceFactory.refinementCancelled(
      runID: UUID(), startedAt: start, finishedAt: finish, model: "model",
      profile: .concise, sourceText: "source", endpointLabel: "loopback",
      endpointLocality: .local, reason: .viewClosed)
    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertEqual(cancelled.cancellation?.reason, .viewClosed)
    XCTAssertNil(cancelled.outputText)
    XCTAssertNil(cancelled.error)
    XCTAssertTrue(cancelled.isConsistent)
  }

  func testComparisonSkipsPendingAndRunning() throws {
    let candidate = try PromptComparisonCandidate(id: "c", model: "m", profile: .concise)
    for status in [PromptCandidateRunStatus.pending, .running] {
      let result = PromptCandidateResult(candidate: candidate, status: status)
      XCTAssertNil(
        try RunTraceFactory.comparison(
          result: result, sourceText: "s", endpointLabel: "loopback", endpointLocality: .local))
    }
    let cancelledBeforeStart = PromptCandidateResult(
      candidate: try PromptComparisonCandidate(id: "cancelled", model: "m", profile: .concise),
      status: .cancelled)
    XCTAssertNil(
      try RunTraceFactory.comparison(
        result: cancelledBeforeStart, sourceText: "s", endpointLabel: "loopback", endpointLocality: .local))
  }

  func testComparisonMapsCompletedFailedAndCancelled() throws {
    let candidate = try PromptComparisonCandidate(id: "c", model: "m", profile: .concise)
    let error = RunError(domain: "provider", code: 7, message: "offline")
    let cases = [
      PromptCandidateResult(
        candidate: candidate, status: .completed, compiledPrompt: "out", startedAt: start,
        finishedAt: finish),
      PromptCandidateResult(
        candidate: candidate, status: .failed, error: error, startedAt: start, finishedAt: finish),
      PromptCandidateResult(
        candidate: candidate, status: .cancelled, startedAt: start, finishedAt: finish),
    ]
    let traces = try cases.map {
      try XCTUnwrap(
        RunTraceFactory.comparison(
          result: $0, sourceText: "s", endpointLabel: "loopback", endpointLocality: .local))
    }
    XCTAssertEqual(traces.map(\.status), [.completed, .failed, .cancelled])
    XCTAssertTrue(traces.allSatisfy(\.isConsistent))
    XCTAssertThrowsError(
      try RunTraceFactory.comparison(
        result: PromptCandidateResult(
          candidate: candidate, status: .failed, startedAt: start, finishedAt: finish),
        sourceText: "s", endpointLabel: "loopback", endpointLocality: .local))
  }

  func testComparisonBatchRejectsMalformedTerminalCandidateBeforeReturningPrefix() throws {
    let validCandidate = try PromptComparisonCandidate(id: "valid", model: "m", profile: .concise)
    let invalidCandidate = try PromptComparisonCandidate(id: "invalid", model: "m", profile: .concise)
    let result = PromptComparisonResult(
      sourceText: "source",
      candidates: [
        PromptCandidateResult(
          candidate: validCandidate, status: .completed, compiledPrompt: "out",
          startedAt: start, finishedAt: finish),
        PromptCandidateResult(
          candidate: invalidCandidate, status: .failed,
          startedAt: start, finishedAt: finish)
      ], startedAt: start, finishedAt: finish)

    XCTAssertThrowsError(
      try RunTraceFactory.comparisonBatch(
        result: result, endpointLabel: "loopback", endpointLocality: .local))
  }

  func testEvaluationUsesResultTimingAndRejectsMismatches() throws {
    let evalCase = EvalCase(
      id: "case", name: "Case", input: "ticket",
      checks: [EvalCheck(id: "c", kind: .nonEmpty)])
    let suite = EvalSuite(id: "s", name: "S", cases: [evalCase])
    let candidate = EvalCandidateConfiguration(
      id: "candidate", label: "Candidate", model: "m", instruction: "extract")
    let result = EvalCaseResult(
      caseID: "case", suiteCaseVersion: 1, candidateID: "candidate", candidateLabel: "Candidate",
      candidateVersion: 1, model: "m", output: "json", error: nil,
      checkResults: [EvalCheckResult(checkID: "c", label: "c", passed: true, detail: "Passed")],
      latencyMilliseconds: 10, inputTokenCount: 2, outputTokenCount: 3,
      startedAt: start, finishedAt: finish)
    let trace = try RunTraceFactory.evaluation(
      result: result, suite: suite, candidate: candidate, endpointLabel: "loopback",
      endpointLocality: .local)
    XCTAssertEqual(trace.startedAt, start)
    XCTAssertEqual(trace.finishedAt, finish)
    XCTAssertEqual(trace.outputText, "json")
    XCTAssertTrue(trace.isConsistent)

    let mismatched = EvalCaseResult(
      caseID: "other", suiteCaseVersion: 1, candidateID: "candidate", candidateLabel: "Candidate",
      candidateVersion: 1, model: "m", output: nil, error: nil, checkResults: [],
      latencyMilliseconds: nil, inputTokenCount: nil, outputTokenCount: nil,
      startedAt: start, finishedAt: finish)
    XCTAssertThrowsError(
      try RunTraceFactory.evaluation(
        result: mismatched, suite: suite, candidate: candidate, endpointLabel: "loopback",
        endpointLocality: .local))
  }

  func testEvaluationRejectsMissingOrReversedTiming() throws {
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [EvalCase(id: "case", name: "Case", input: "ticket", checks: [])])
    let candidate = EvalCandidateConfiguration(
      id: "candidate", label: "Candidate", model: "m", instruction: "extract")
    let result = EvalCaseResult(
      caseID: "case", suiteCaseVersion: 1, candidateID: "candidate", candidateLabel: "Candidate",
      candidateVersion: 1, model: "m", output: nil, error: nil, checkResults: [],
      latencyMilliseconds: nil, inputTokenCount: nil, outputTokenCount: nil)
    XCTAssertThrowsError(
      try RunTraceFactory.evaluation(
        result: result, suite: suite, candidate: candidate, endpointLabel: "loopback",
        endpointLocality: .local))
  }
}
