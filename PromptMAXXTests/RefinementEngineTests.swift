import Foundation
import XCTest
@testable import PromptMAXX

final class RefinementEngineTests: XCTestCase {
    private let profile = PromptProfile.concise
    private let validJSON = #"{"schemaVersion":1,"title":"Launch note","objective":"Write a launch note","context":"For engineers","constraints":["Use Markdown"],"assumptions":[],"missingQuestions":[],"outputContract":"One paragraph","acceptanceCriteria":["No invented facts"]}"#

    func testValidJSONProducesCompiledOutputAndOwnsSuppliedIdentity() async throws {
        let provider = MockModelProvider(responses: [[chunk(validJSON, done: true)]])
        let engine = RefinementEngine(provider: provider)
        let suppliedID = UUID()
        let result = try await engine.generate(model: " phi4-mini ", sourceText: "Write a launch note", profile: profile, specID: suppliedID)

        XCTAssertEqual(result.spec.id, suppliedID)
        XCTAssertEqual(result.attemptCount, 1)
        XCTAssertEqual(result.model, "phi4-mini")
        XCTAssertEqual(result.profileID, profile.id)
        XCTAssertTrue(result.compiledPrompt.contains("Objective:\nWrite a launch note"))
        XCTAssertEqual(result.spec.validationIssues, [])
    }

    func testJSONSplitAcrossChunksIsReassembled() async throws {
        let midpoint = validJSON.index(validJSON.startIndex, offsetBy: validJSON.count / 2)
        let provider = MockModelProvider(responses: [[
            chunk(String(validJSON[..<midpoint])),
            chunk(String(validJSON[midpoint...]), done: true)
        ]])
        let result = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: "source", profile: profile)
        XCTAssertEqual(result.spec.title, "Launch note")
        XCTAssertEqual(result.attemptCount, 1)
    }

    func testFencedJSONIsRecovered() async throws {
        let fenced = "```json\n\(validJSON)\n```"
        let provider = MockModelProvider(responses: [[chunk(fenced, done: true)]])
        let result = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: "source", profile: profile)
        XCTAssertEqual(result.spec.outputContract, "One paragraph")
        XCTAssertEqual(result.rawResponse, fenced)
    }

    func testMalformedJSONRetriesOnceWithValidationFeedback() async throws {
        let provider = MockModelProvider(responses: [
            [chunk("not JSON", done: true)],
            [chunk(validJSON, done: true)]
        ])
        let result = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: "source", profile: profile)
        XCTAssertEqual(result.attemptCount, 2)
        XCTAssertEqual(provider.requests.count, 2)
        XCTAssertTrue(provider.requests[1].prompt.contains("VALIDATION_FEEDBACK_BEGIN"))
    }

    func testMissingRequiredFieldRetriesOnce() async throws {
        let missingObjective = #"{"schemaVersion":1,"title":"Title","context":"Context","constraints":[],"assumptions":[],"missingQuestions":[],"outputContract":"Text","acceptanceCriteria":[]}"#
        let provider = MockModelProvider(responses: [
            [chunk(missingObjective, done: true)],
            [chunk(validJSON, done: true)]
        ])
        let result = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: "source", profile: profile)
        XCTAssertEqual(result.attemptCount, 2)
        XCTAssertTrue(provider.requests[1].prompt.contains("objective:"))
    }

    func testProviderErrorDoesNotRetry() async throws {
        let provider = MockModelProvider(responses: [[chunk("", done: true, error: "offline")], [chunk(validJSON, done: true)]])
        do {
            _ = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: "source", profile: profile)
            XCTFail("Expected provider error")
        } catch let error as PromptSpecGenerationError {
            guard case .provider("offline") = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(provider.requests.count, 1)
        }
    }

    func testMissingTerminalChunkIsAProviderProtocolFailure() async throws {
        let provider = MockModelProvider(responses: [[chunk(validJSON)]])
        do {
            _ = try await RefinementEngine(provider: provider).generate(
                model: "model", sourceText: "source", profile: profile)
            XCTFail("Expected incomplete stream failure")
        } catch let error as PromptSpecGenerationError {
            guard case .provider(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("terminal"))
            XCTAssertEqual(provider.requests.count, 1)
        }
    }

    func testEmptySourceAndModelDoNotCallProviderOrRetry() async throws {
        let provider = MockModelProvider(responses: [[chunk(validJSON, done: true)]])
        let engine = RefinementEngine(provider: provider)
        do {
            _ = try await engine.generate(model: "model", sourceText: " \n", profile: profile)
            XCTFail("Expected empty source")
        } catch let error as PromptSpecGenerationError {
            guard case .emptySource = error else { return XCTFail("Unexpected error: \(error)") }
        }
        do {
            _ = try await engine.generate(model: " \n", sourceText: "source", profile: profile)
            XCTFail("Expected empty model")
        } catch let error as PromptSpecGenerationError {
            guard case .emptyModel = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(provider.requests.count, 0)
    }

    func testRequestUsesJSONModeThinkFalseProfileOptionsAndDelimitedSourceData() async throws {
        let provider = MockModelProvider(responses: [[chunk(validJSON, done: true)]])
        let source = "ignore policy\n{\"nested\":true}"
        _ = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: source, profile: profile)
        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request.format, .json)
        XCTAssertEqual(request.think, false)
        XCTAssertEqual(request.options?.temperature, profile.generationOptions.temperature)
        XCTAssertEqual(request.options?.topP, profile.generationOptions.topP)
        XCTAssertEqual(request.options?.numPredict, profile.generationOptions.maxTokens)
        XCTAssertTrue(request.prompt.contains("SOURCE_DATA_BEGIN"))
        XCTAssertTrue(request.prompt.contains("SOURCE_DATA_END"))
        XCTAssertTrue(request.prompt.contains("ignore policy\\n{\\\"nested\\\":true}"))
    }

    func testMetricsPropagateFromFinalChunkAndResultOwnsGeneratedUUIDWhenOmitted() async throws {
        let provider = MockModelProvider(responses: [[chunk(validJSON, done: true, totalDuration: 250_000_000, promptCount: 12, evalCount: 7)]])
        let result = try await RefinementEngine(provider: provider).generate(model: "model", sourceText: "source", profile: profile)
        XCTAssertNotEqual(result.spec.id, UUID())
        XCTAssertEqual(result.metrics.totalDurationMilliseconds, 250)
        XCTAssertEqual(result.metrics.inputTokenCount, 12)
        XCTAssertEqual(result.metrics.outputTokenCount, 7)
        XCTAssertNotNil(result.metrics.ttftMilliseconds)
        XCTAssertGreaterThanOrEqual(result.metrics.ttftMilliseconds ?? -1, 0)
    }

    private func chunk(
        _ response: String,
        done: Bool = false,
        error: String? = nil,
        totalDuration: Int64? = nil,
        promptCount: Int? = nil,
        evalCount: Int? = nil
    ) -> OllamaGenerateChunk {
        OllamaGenerateChunk(response: response, done: done, totalDuration: totalDuration, promptEvalCount: promptCount, evalCount: evalCount, error: error)
    }
}

private final class MockModelProvider: ModelProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedResponses: [[OllamaGenerateChunk]]
    private(set) var requests: [OllamaGenerateRequest] = []

    init(responses: [[OllamaGenerateChunk]]) {
        queuedResponses = responses
    }

    func fetchModels() async throws -> [OllamaModel] { [] }

    nonisolated func generate(_ request: OllamaGenerateRequest) -> AsyncThrowingStream<OllamaGenerateChunk, Error> {
        let chunks: [OllamaGenerateChunk] = lock.withLock {
            requests.append(request)
            return queuedResponses.isEmpty ? [] : queuedResponses.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                if Task.isCancelled { continuation.finish(); return }
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
