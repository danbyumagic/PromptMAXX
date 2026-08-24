import Foundation
import XCTest

@testable import PromptMAXX

final class EvaluationTests: XCTestCase {
  func testChecksAndSafeRegex() {
    let output = #"{"items":[{"name":"one"}],"text":"Keep concise"}"#
    XCTAssertTrue(EvalCheck(id: "j", kind: .validJSON).evaluate(output).passed)
    XCTAssertTrue(
      EvalCheck(id: "p", kind: .requiredJSONPath, value: "items.0.name").evaluate(output).passed)
    XCTAssertTrue(
      EvalCheck(id: "r", kind: .regex, value: "[").evaluate(output).detail
        == "Invalid regular expression")
  }

  func testExactJSONPathScalarEqualityIsTypeSensitiveAndDistinguishesMissing() throws {
    let output =
      #"{"ticket":{"owner":"identity","urgent":true,"count":2,"none":null},"items":[{"id":"A"}]}"#
    XCTAssertTrue(
      EvalCheck(
        id: "s", kind: .equalsJSONPath, value: "ticket.owner", expected: .string("identity")
      ).evaluate(output).passed)
    XCTAssertTrue(
      EvalCheck(id: "b", kind: .equalsJSONPath, value: "ticket.urgent", expected: .bool(true))
        .evaluate(output).passed)
    XCTAssertTrue(
      EvalCheck(id: "n", kind: .equalsJSONPath, value: "ticket.count", expected: .number(2))
        .evaluate(output).passed)
    XCTAssertTrue(
      EvalCheck(id: "null", kind: .equalsJSONPath, value: "ticket.none", expected: .null).evaluate(
        output
      ).passed)
    XCTAssertTrue(
      EvalCheck(id: "array", kind: .equalsJSONPath, value: "items.0.id", expected: .string("A"))
        .evaluate(output).passed)
    let mismatch = EvalCheck(
      id: "m", kind: .equalsJSONPath, value: "ticket.count", expected: .string("2")
    ).evaluate(output)
    XCTAssertFalse(mismatch.passed)
    XCTAssertTrue(mismatch.detail.contains("ticket.count"))
    XCTAssertTrue(mismatch.detail.contains("expected string \"2\", got number 2.0"))
    let missing = EvalCheck(id: "x", kind: .equalsJSONPath, value: "ticket.absent", expected: .null)
      .evaluate(output)
    XCTAssertFalse(missing.passed)
    XCTAssertTrue(missing.detail.contains("path is missing"))
  }

  func testExactJSONPathValidationAndCodableCompatibility() throws {
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [
        EvalCase(
          id: "c", name: "C", input: "x",
          checks: [EvalCheck(id: "x", kind: .equalsJSONPath, value: "owner")])
      ])
    XCTAssertThrowsError(try suite.validate())
    let check = EvalCheck(
      id: "x", kind: .equalsJSONPath, value: "owner", expected: .string("identity"))
    let decoded = try JSONDecoder().decode(EvalCheck.self, from: JSONEncoder().encode(check))
    XCTAssertEqual(decoded, check)
    let legacy = try JSONDecoder().decode(
      EvalCheck.self,
      from: Data(#"{"id":"x","kind":"requiredJSONPath","value":"owner","label":""}"#.utf8))
    XCTAssertNil(legacy.expected)
  }
  func testBuiltInIsCoherentAndCandidatesAreStable() throws {
    let s = BuiltInBenchmark.suite
    try s.validate()
    XCTAssertEqual(s.cases.count, 8)
    XCTAssertEqual(BuiltInBenchmark.originalCandidate().id, "original-v1")
    XCTAssertEqual(BuiltInBenchmark.refinedCandidate().id, "refined-v1")
    XCTAssertTrue(s.cases.flatMap(\.checks).contains { $0.kind == .equalsJSONPath })
  }
  func testRunsEveryCandidateAgainstSameOrderedCasesAndAggregates() async throws {
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [
        EvalCase(
          id: "a", name: "A", input: "one", checks: [EvalCheck(id: "json", kind: .validJSON)]),
        EvalCase(
          id: "b", name: "B", input: "two", checks: [EvalCheck(id: "json", kind: .validJSON)]),
      ])
    let candidates = [
      EvalCandidateConfiguration(
        id: "original", label: "Original", model: "m1", instruction: "original", format: .json),
      EvalCandidateConfiguration(
        id: "refined", label: "Refined", model: "m2", instruction: "refined", format: .json),
    ]
    let provider = EvaluationMockProvider(responses: [
      [chunk("{\"ok\":true}", done: true)], [chunk("bad", done: true)],
      [chunk("{\"ok\":true}", done: true)], [chunk("{\"ok\":true}", done: true)],
    ])
    let report = try await EvaluationRunner(provider: provider).run(
      EvalRunRequest(suite: suite, candidates: candidates))
    XCTAssertEqual(
      report.results.map(\.id), ["original::a", "original::b", "refined::a", "refined::b"])
    XCTAssertEqual(report.summaries.map(\.candidateID), ["original", "refined"])
    XCTAssertEqual(report.summaries[0].passedCases, 1)
    XCTAssertEqual(report.summaries[1].passedCases, 2)
    XCTAssertTrue(provider.requests[0].prompt.contains("EVALUATION_DATA_BEGIN"))
    XCTAssertEqual(provider.requests[0].format, .json)
  }
  func testProviderErrorPreservesPartialOutputAndCandidateIdentity() async throws {
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [
        EvalCase(id: "a", name: "A", input: "one", checks: [EvalCheck(id: "n", kind: .nonEmpty)])
      ])
    let candidate = EvalCandidateConfiguration(
      id: "c", version: 3, label: "Demo", model: "m", instruction: "extract")
    let provider = EvaluationMockProvider(responses: [
      [chunk("partial "), chunk("", done: true, error: "offline")]
    ])
    let report = try await EvaluationRunner(provider: provider).run(
      EvalRunRequest(suite: suite, candidates: [candidate]))
    let r = report.results[0]
    XCTAssertEqual(r.output, "partial ")
    XCTAssertEqual(r.error, "offline")
    XCTAssertEqual(r.candidateID, "c")
    XCTAssertEqual(r.candidateVersion, 3)
  }

  func testMissingTerminalChunkIsRecordedAsProtocolFailure() async throws {
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [
        EvalCase(id: "a", name: "A", input: "one", checks: [EvalCheck(id: "n", kind: .nonEmpty)])
      ])
    let candidate = EvalCandidateConfiguration(id: "c", label: "C", model: "m", instruction: "extract")
    let provider = EvaluationMockProvider(responses: [[chunk("partial")]])
    let report = try await EvaluationRunner(provider: provider).run(
      EvalRunRequest(suite: suite, candidates: [candidate]))

    XCTAssertEqual(report.results.count, 1)
    XCTAssertTrue(report.results[0].error?.contains("terminal") == true)
    XCTAssertEqual(report.results[0].output, "partial")
  }

  func testPerCaseObservationReceivesCompletedAndFailedCasesInOrder() async throws {
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [
        EvalCase(id: "a", name: "A", input: "one", checks: [EvalCheck(id: "n", kind: .nonEmpty)]),
        EvalCase(id: "b", name: "B", input: "two", checks: [EvalCheck(id: "n", kind: .nonEmpty)]),
      ])
    let candidate = EvalCandidateConfiguration(
      id: "c", label: "C", model: "m", instruction: "extract")
    let recorder = EvaluationObservationRecorder()
    let provider = EvaluationMockProvider(responses: [
      [chunk("ok", done: true)], [chunk("", done: true, error: "offline")],
    ])

    _ = try await EvaluationRunner(provider: provider).run(
      EvalRunRequest(suite: suite, candidates: [candidate])
    ) { result in
      await recorder.append(result)
    }

    let observed = await recorder.results
    XCTAssertEqual(observed.map(\.id), ["c::a", "c::b"])
    XCTAssertNil(observed[0].error)
    XCTAssertEqual(observed[1].error, "offline")
  }
  func testValidationRejectsEmptyDuplicateIDsAndMissingConfiguration() async throws {
    let empty = EvalSuite(id: "s", name: "S", cases: [])
    let c = EvalCandidateConfiguration(id: "c", label: "C", model: "m", instruction: "i")
    do {
      _ = try await EvaluationRunner(provider: EvaluationMockProvider(responses: [])).run(
        EvalRunRequest(suite: empty, candidates: [c]))
      XCTFail()
    } catch let e as EvaluationConfigurationError {
      XCTAssertTrue(e.localizedDescription.contains("at least one"))
    }
    let suite = EvalSuite(
      id: "s", name: "S",
      cases: [
        EvalCase(id: "a", name: "A", input: "x", checks: [EvalCheck(id: "x", kind: .nonEmpty)])
      ])
    let dup = EvalCandidateConfiguration(id: "c", label: "C", model: "m", instruction: "i")
    let whitespaceVariant = EvalCandidateConfiguration(
      id: " c ", label: "C2", model: "m", instruction: "i")
    do {
      _ = try await EvaluationRunner(provider: EvaluationMockProvider(responses: [])).run(
        EvalRunRequest(suite: suite, candidates: [dup, whitespaceVariant]))
      XCTFail()
    } catch let e as EvaluationConfigurationError {
      XCTAssertTrue(e.localizedDescription.contains("unique"))
    }
  }
  func testExportsReportWithReproducibleConfigurationAndDates() throws {
    let result = EvalCaseResult(
      caseID: "a", suiteCaseVersion: 1, candidateID: "c", candidateLabel: "C", candidateVersion: 1,
      model: "m", output: "x", error: nil,
      checkResults: [EvalCheckResult(checkID: "x", label: "x", passed: true, detail: "Passed")],
      latencyMilliseconds: 1, inputTokenCount: 1, outputTokenCount: 2)
    let suite = EvalSuite(
      id: "s", name: "Suite",
      cases: [
        EvalCase(id: "a", name: "A", input: "x", checks: [EvalCheck(id: "x", kind: .nonEmpty)])
      ])
    let candidate = EvalCandidateConfiguration(id: "c", label: "C", model: "m", instruction: "i")
    let report = EvalReport(
      suite: suite, candidates: [candidate], startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 1), results: [result])
    XCTAssertTrue(report.markdown().contains("100.0%"))
    let exported = String(decoding: try report.jsonData(), as: UTF8.self)
    XCTAssertTrue(exported.contains("instruction"))
    XCTAssertTrue(exported.contains("generationOptions"))
    XCTAssertTrue(exported.contains("checks"))
    XCTAssertTrue(exported.contains("1970-01-01T00:00:00Z"))
    XCTAssertTrue(exported.contains("\n  \"suite\""))
  }

  func testPreCancelledTaskMakesZeroProviderRequests() async throws {
    let provider = EvaluationMockProvider(responses: [])
    let runner = EvaluationRunner(provider: provider)
    let recorder = EvaluationObservationRecorder()
    let request = EvalRunRequest(
      suite: BuiltInBenchmark.suite, candidates: [BuiltInBenchmark.originalCandidate()])
    let task = Task { () throws -> EvalReport in
      try Task.checkCancellation()
      return try await runner.run(request) { result in
        await recorder.append(result)
      }
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(provider.requests.count, 0)
      let observedCount = await recorder.results.count
      XCTAssertEqual(observedCount, 0)
    }
  }
  private func chunk(
    _ response: String, done: Bool = false, error: String? = nil
  ) -> OllamaGenerateChunk {
    OllamaGenerateChunk(response: response, done: done, error: error)
  }
}

private actor EvaluationObservationRecorder {
  private(set) var results: [EvalCaseResult] = []

  func append(_ result: EvalCaseResult) {
    results.append(result)
  }
}

private final class EvaluationMockProvider: ModelProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [[OllamaGenerateChunk]]
  private(set) var requests: [OllamaGenerateRequest] = []
  init(responses: [[OllamaGenerateChunk]]) { self.responses = responses }
  func fetchModels() async throws -> [OllamaModel] { [] }
  nonisolated func generate(_ request: OllamaGenerateRequest) -> AsyncThrowingStream<
    OllamaGenerateChunk, Error
  > {
    let chunks = lock.withLock {
      requests.append(request)
      return responses.isEmpty ? [] : responses.removeFirst()
    }
    return AsyncThrowingStream { c in
      for x in chunks { c.yield(x) }
      c.finish()
    }
  }
}
