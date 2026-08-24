import Foundation
import XCTest
@testable import PromptMAXX

final class PromptComparisonTests: XCTestCase {
    func testConfigurationPreservesCandidateOrderAndRejectsInvalidCount() throws {
        let first = try PromptComparisonCandidate(id: "first", model: "model-a", profile: .concise)
        let second = try PromptComparisonCandidate(id: "second", model: "model-b", profile: .structured)
        let configuration = try PromptComparisonConfiguration(sourceText: "Make this clear", candidates: [first, second])
        XCTAssertEqual(configuration.candidates.map(\.id), ["first", "second"])

        XCTAssertThrowsError(try PromptComparisonConfiguration(sourceText: "source", candidates: [first]))
        XCTAssertThrowsError(try PromptComparisonConfiguration(sourceText: "source", candidates: [first, second, first]))
        XCTAssertThrowsError(try PromptComparisonConfiguration(sourceText: "   ", candidates: [first, second]))
        let five = [first, second, first, second, first]
        XCTAssertThrowsError(try PromptComparisonConfiguration(sourceText: "source", candidates: five))
    }

    func testRejectsEmptyOrDuplicateCandidateIDsAndInvalidConcurrency() throws {
        XCTAssertThrowsError(try PromptComparisonCandidate(id: "  ", model: "model", profile: .concise))
        XCTAssertThrowsError(try PromptComparisonCandidate(id: "candidate", model: "  ", profile: .concise))

        let first = try PromptComparisonCandidate(id: "same", model: "one", profile: .concise)
        let duplicate = try PromptComparisonCandidate(id: "same", model: "two", profile: .structured)
        XCTAssertThrowsError(try PromptComparisonConfiguration(sourceText: "source", candidates: [first, duplicate]))

        let provider = ComparisonFixtureProvider()
        XCTAssertThrowsError(try PromptComparisonRunner(provider: provider, maxConcurrent: 0))
        XCTAssertThrowsError(try PromptComparisonRunner(provider: provider, maxConcurrent: 5))
    }

    func testRunnerReturnsStableResultsAndCapturesValidationFailure() async throws {
        let provider = ComparisonFixtureProvider()
        let runner = try PromptComparisonRunner(provider: provider, maxConcurrent: 2)
        let candidates = [
            try PromptComparisonCandidate(id: "good", model: "good-model", profile: .concise),
            try PromptComparisonCandidate(id: "bad", model: "bad-model", profile: .structured)
        ]
        let configuration = try PromptComparisonConfiguration(sourceText: "Write a summary", candidates: candidates)

        let result = await runner.compare(configuration)
        XCTAssertEqual(result.candidates.map(\.id), ["good", "bad"])
        XCTAssertEqual(result.candidates[0].status, .completed)
        XCTAssertNotNil(result.candidates[0].compiledPrompt)
        XCTAssertEqual(result.candidates[0].attempts, 1)
        XCTAssertEqual(result.candidates[1].status, .failed)
        XCTAssertEqual(result.candidates[1].attempts, 0)
        XCTAssertNotNil(result.candidates[1].validationFailure)
        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.failedCount, 1)
    }

    func testProviderFailureIsRecordedWithoutFabricatingAttempts() async throws {
        let provider = ComparisonFixtureProvider(failingModels: ["offline-model"])
        let runner = try PromptComparisonRunner(provider: provider)
        let candidates = [
            try PromptComparisonCandidate(id: "offline", model: "offline-model", profile: .concise),
            try PromptComparisonCandidate(id: "good", model: "good-model", profile: .structured)
        ]
        let result = await runner.compare(try PromptComparisonConfiguration(sourceText: "source", candidates: candidates))

        XCTAssertEqual(result.candidates[0].status, .failed)
        XCTAssertEqual(result.candidates[0].attempts, 0)
        XCTAssertTrue(result.candidates[0].error?.message.contains("offline") == true)
        XCTAssertEqual(result.candidates[1].status, .completed)
    }

    func testOutOfOrderConcurrentCompletionKeepsStableOrdering() async throws {
        let provider = ComparisonFixtureProvider(delays: ["slow-model": 0.08, "fast-model": 0.01, "instant-model": 0])
        let runner = try PromptComparisonRunner(provider: provider, maxConcurrent: 2)
        let candidates = [
            try PromptComparisonCandidate(id: "slow", model: "slow-model", profile: .concise),
            try PromptComparisonCandidate(id: "fast", model: "fast-model", profile: .structured),
            try PromptComparisonCandidate(id: "instant", model: "instant-model", profile: .preserveVoice)
        ]
        let result = await runner.compare(try PromptComparisonConfiguration(sourceText: "source", candidates: candidates))

        XCTAssertEqual(result.candidates.map(\.id), ["slow", "fast", "instant"])
        XCTAssertTrue(result.candidates.allSatisfy { $0.status == .completed })
    }

    func testCancelledParentDoesNotStartAnyCandidateOrLaterBatch() async throws {
        let provider = ComparisonFixtureProvider(delays: ["slow-model": 0.2, "later-model": 0.01])
        let runner = try PromptComparisonRunner(provider: provider, maxConcurrent: 1)
        let candidates = [
            try PromptComparisonCandidate(id: "first", model: "slow-model", profile: .concise),
            try PromptComparisonCandidate(id: "second", model: "later-model", profile: .structured)
        ]
        let configuration = try PromptComparisonConfiguration(sourceText: "source", candidates: candidates)

        let task = Task { await runner.compare(configuration) }
        for _ in 0..<40 where provider.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.candidates.allSatisfy { $0.status == .cancelled })
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(result.candidates.allSatisfy { $0.attempts == 0 })
    }
}

private final class ComparisonFixtureProvider: ModelProvider, @unchecked Sendable {
    private let delays: [String: TimeInterval]
    private let failingModels: Set<String>
    private let lock = NSLock()
    private var calls = 0

    init(delays: [String: TimeInterval] = [:], failingModels: Set<String> = []) {
        self.delays = delays
        self.failingModels = failingModels
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func fetchModels() async throws -> [OllamaModel] { [] }

    func generate(_ request: OllamaGenerateRequest) -> AsyncThrowingStream<OllamaGenerateChunk, Error> {
        lock.lock()
        calls += 1
        lock.unlock()

        let response: String
        if request.model == "bad-model" {
            response = #"{"schemaVersion":1,"title":"Missing fields","objective":"","outputContract":""}"#
        } else {
            response = #"{"schemaVersion":1,"title":"Summary","objective":"Summarize the source","context":"","constraints":[],"assumptions":[],"missingQuestions":[],"outputContract":"A concise summary","acceptanceCriteria":[]}"#
        }

        return AsyncThrowingStream { continuation in
            Task {
                let delay = self.delays[request.model] ?? 0
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                if self.failingModels.contains(request.model) {
                    continuation.finish(throwing: OllamaClientError.transport("offline"))
                    return
                }
                continuation.yield(OllamaGenerateChunk(
                    response: response,
                    done: true,
                    totalDuration: 2_000_000,
                    promptEvalCount: 4,
                    evalCount: 8
                ))
                continuation.finish()
            }
        }
    }
}
