import Foundation
import XCTest

@testable import PromptMAXX

private struct BenchmarkFixtureEmbeddingProvider: EmbeddingProvider {
  let delayNanoseconds: UInt64
  let failingInputs: Set<String>

  init(delayNanoseconds: UInt64 = 0, failingInputs: Set<String> = []) {
    self.delayNanoseconds = delayNanoseconds
    self.failingInputs = failingInputs
  }

  func embed(model: String, input: String, dimensions: Int?) async throws -> OllamaEmbedResponse {
    try await embed(model: model, inputs: [input], dimensions: dimensions)
  }

  func embed(model: String, inputs: [String], dimensions: Int?) async throws -> OllamaEmbedResponse {
    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }
    if let input = inputs.first, failingInputs.contains(input) {
      throw FixtureError.failed(input)
    }
    let vectors = inputs.map(vector(for:))
    return OllamaEmbedResponse(
      model: model, embeddings: vectors, totalDuration: nil, loadDuration: nil,
      promptEvalCount: nil)
  }

  private func vector(for input: String) -> [Double] {
    let lowercased = input.lowercased()
    let alpha = lowercased.contains("alpha")
    let beta = lowercased.contains("beta")
    let gamma = lowercased.contains("gamma")
    return [alpha ? 1 : 0, beta ? 1 : 0, gamma ? 1 : 0]
      .map { $0 == 0 && !alpha && !beta && !gamma ? 0.1 : $0 }
  }

  private enum FixtureError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
      switch self {
      case .failed(let input): return "Fixture provider failed for \(input)."
      }
    }
  }
}

final class GroundingBenchmarkTests: XCTestCase {
  func testDemoSuiteIsVersionedSplitAndDeterministicWithoutFixtureLoss() throws {
    let first = try GroundingBenchmarkSuite.makeDemo()
    let second = try GroundingBenchmarkSuite.makeDemo()

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.corpus.id, "promptmaxx-grounding-demo")
    XCTAssertEqual(first.corpus.version, GroundingBenchmarkCorpus.currentVersion)
    XCTAssertEqual(first.corpus.sources.count, 8)
    XCTAssertEqual(first.queries.count, 20)
    XCTAssertEqual(first.tuningCount, 10)
    XCTAssertEqual(first.heldOutCount, 10)
    XCTAssertEqual(Set(first.corpus.sources.map(\.id)).count, 8)
    XCTAssertTrue(first.queries.contains { $0.relevantSourceIDs.count > 1 })
    XCTAssertEqual(first.queries(for: .heldOut).count, 10)
    XCTAssertEqual(first.queries(for: .tuning).count, 10)
  }

  func testRunnerPreservesMetadataOutcomesAndCountsErrorsAsMisses() async throws {
    let alpha = try GroundingSource.text(name: "Alpha", text: "alpha source", id: "alpha")
    let beta = try GroundingSource.text(name: "Beta", text: "beta source", id: "beta")
    let gamma = try GroundingSource.text(name: "Gamma", text: "gamma distractor", id: "gamma")
    let corpus = try GroundingBenchmarkCorpus(id: "fixture-corpus", sources: [alpha, beta, gamma])
    let queries = try [
      GroundingBenchmarkQuery(id: "q-alpha", query: "alpha", relevantSourceIDs: ["alpha"], split: .heldOut),
      GroundingBenchmarkQuery(id: "q-both", query: "alpha beta", relevantSourceIDs: ["alpha", "beta"], split: .heldOut),
      GroundingBenchmarkQuery(id: "q-broken", query: "broken", relevantSourceIDs: ["gamma"], split: .heldOut),
    ]
    let suite = try GroundingBenchmarkSuite(
      id: "fixture-suite", name: "Fixture", corpus: corpus, queries: queries)
    let runner = GroundingBenchmarkRunner(
      embeddingProvider: BenchmarkFixtureEmbeddingProvider(failingInputs: ["broken"]),
      clock: { FixedBenchmarkClock.date })
    let configuration = try GroundingBenchmarkConfiguration(
      embeddingModel: "fixture-model",
      dimensions: 3,
      chunkSize: 100,
      overlap: 0,
      lexicalWeight: 0,
      mmrLambda: 1,
      sameSourcePenalty: 0,
      topK: 2,
      characterBudget: 1_000,
      split: .heldOut)

    let report = try await runner.run(suite: suite, configuration: configuration)
    XCTAssertEqual(report.metadata.suiteID, "fixture-suite")
    XCTAssertEqual(report.metadata.corpusID, "fixture-corpus")
    XCTAssertEqual(report.metadata.dimensions, 3)
    XCTAssertEqual(report.metadata.timestamp, FixedBenchmarkClock.date)
    XCTAssertEqual(report.outcomes.count, 3)
    XCTAssertEqual(report.aggregate.totalCases, 3)
    XCTAssertEqual(report.aggregate.evaluatedCases, 2)
    XCTAssertEqual(report.aggregate.errorCount, 1)
    XCTAssertEqual(report.aggregate.hits, 2)
    XCTAssertEqual(report.aggregate.hitRateAtK, 2.0 / 3.0, accuracy: 0.000_001)
    XCTAssertEqual(report.aggregate.recallAtK, 2.0 / 3.0, accuracy: 0.000_001)
    XCTAssertEqual(report.aggregate.sourceCoverage, 2.0 / 3.0, accuracy: 0.000_001)
    XCTAssertEqual(report.outcomes.first { $0.id == "q-both" }?.relevantSourceIDs, ["alpha", "beta"])
    XCTAssertEqual(report.outcomes.first { $0.id == "q-broken" }?.status, .error)
  }

  func testReportExportsSortedISOJSONAndHonestMarkdown() async throws {
    let suite = try GroundingBenchmarkSuite.makeDemo()
    let runner = GroundingBenchmarkRunner(
      embeddingProvider: BenchmarkFixtureEmbeddingProvider(),
      clock: { FixedBenchmarkClock.date })
    let configuration = try GroundingBenchmarkConfiguration(
      embeddingModel: "fixture-model", dimensions: 3, chunkSize: 1_000, overlap: 0, topK: 3,
      characterBudget: 2_000, split: .heldOut, endpointLocality: .remote)
    let report = try await runner.run(suite: suite, configuration: configuration)
    let firstJSON = try report.jsonData()
    let secondJSON = try report.jsonData()
    XCTAssertEqual(firstJSON, secondJSON)
    let json = try XCTUnwrap(String(data: firstJSON, encoding: .utf8))
    XCTAssertTrue(json.contains("\"aggregate\""), json)
    XCTAssertTrue(json.contains("2024-01-02T03:04:05"))
    XCTAssertTrue(json.contains("\"corpusID\" : \"promptmaxx-grounding-demo\"") || json.contains("\"corpusID\": \"promptmaxx-grounding-demo\""))
    XCTAssertTrue(json.contains("\"endpointLocality\""))
    let markdown = report.markdown()
    XCTAssertTrue(markdown.contains("Hit rate @ k"))
    XCTAssertTrue(markdown.contains("Held-out"))
    XCTAssertTrue(markdown.contains("does not measure answer quality"))
    XCTAssertTrue(markdown.contains("Completed:"))
    XCTAssertTrue(markdown.contains("Expected sources"))
    XCTAssertTrue(markdown.contains("Retrieved chunks"))
    XCTAssertFalse(markdown.contains("confidence score"))
  }

  func testRunnerPropagatesCancellation() async throws {
    let suite = try GroundingBenchmarkSuite.makeDemo()
    let runner = GroundingBenchmarkRunner(
      embeddingProvider: BenchmarkFixtureEmbeddingProvider(delayNanoseconds: 100_000_000))
    let configuration = try GroundingBenchmarkConfiguration(
      embeddingModel: "fixture-model", dimensions: 3, split: .heldOut)
    let task = Task {
      try await runner.run(suite: suite, configuration: configuration)
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected benchmark cancellation")
    } catch is CancellationError {
      // Expected.
    }
  }
}

private nonisolated enum FixedBenchmarkClock {
  // 2024-01-02T03:04:05Z, expressed without a failable formatter so this
  // deterministic test fixture has no fallback path.
  static let date = Date(timeIntervalSince1970: 1_704_164_645)
}
