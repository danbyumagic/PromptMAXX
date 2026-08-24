import Foundation
import XCTest

@testable import PromptMAXX

final class RunTraceModelTests: XCTestCase {
    func testCanonicalHashesAreStableAndContentFieldsAreSensitive() {
        let base = RunTraceTestFixture.trace()
        let same = RunTraceTestFixture.trace()
        XCTAssertEqual(base.contentHash, same.contentHash)
        XCTAssertEqual(base.configurationHash, same.configurationHash)

        let sourceChanged = RunTraceTestFixture.trace(sourceText: "different source")
        XCTAssertNotEqual(base.contentHash, sourceChanged.contentHash)
        XCTAssertEqual(base.configurationHash, sourceChanged.configurationHash)

        let renderedChanged = RunTraceTestFixture.trace(renderedInput: "different rendered")
        XCTAssertNotEqual(base.contentHash, renderedChanged.contentHash)
        XCTAssertEqual(base.configurationHash, renderedChanged.configurationHash)

        let compiledChanged = RunTraceTestFixture.trace(compiledPrompt: "different compiled")
        XCTAssertNotEqual(base.contentHash, compiledChanged.contentHash)
        XCTAssertEqual(base.configurationHash, compiledChanged.configurationHash)

        let outputChangedRun = RunTraceTestFixture.run(output: "different output")
        let outputChanged = RunTraceTestFixture.trace(run: outputChangedRun)
        XCTAssertNotEqual(base.contentHash, outputChanged.contentHash)
        XCTAssertEqual(base.configurationHash, outputChanged.configurationHash)
    }

    func testConfigurationHashIsSensitiveToConfigurationFieldsAndModelVersion() {
        let base = RunTraceTestFixture.trace()
        let providerChanged = RunTraceTestFixture.trace(provider: "other-provider")
        let endpointChanged = RunTraceTestFixture.trace(endpointLabel: "remote")
        let optionsChanged = RunTraceTestFixture.trace(
            generationOptions: PromptGenerationOptions(
                temperature: 0.4, topP: 0.8, maxTokens: 256, seed: 9, stream: false))
        let modelChanged = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(model: "other-model"))
        let profileChanged = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(profileID: "structured"))
        let profileVersionChanged = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(profileVersion: 2))
        let schemaVersionChanged = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(schemaVersion: 2))
        let localityChanged = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(endpointLocality: .remote))
        let modelVersionChanged = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(modelVersion: "digest-b"))

        for candidate in [providerChanged, endpointChanged, optionsChanged, modelChanged,
                          profileChanged, profileVersionChanged, schemaVersionChanged,
                          localityChanged, modelVersionChanged] {
            XCTAssertNotEqual(base.configurationHash, candidate.configurationHash)
        }
    }

    func testInvalidNaNOptionsDoNotCrashAndMakeTraceInconsistent() {
        let trace = RunTraceTestFixture.trace(
            generationOptions: PromptGenerationOptions(temperature: .nan))
        XCTAssertFalse(trace.isConsistent)
        XCTAssertEqual(trace.contentHash.count, 64)
        XCTAssertEqual(trace.configurationHash.count, 64)
    }

    func testSynthesizedJSONPlacesLifecycleOnlyUnderRun() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(RunTraceTestFixture.trace()))
                as? [String: Any])
        let forbiddenTopLevelKeys = [
            "model", "status", "startedAt", "finishedAt", "error", "metrics", "output"
        ]
        for key in forbiddenTopLevelKeys {
            XCTAssertNil(object[key], "Expected lifecycle field only under run: \(key)")
        }
        XCTAssertNotNil(object["run"] as? [String: Any])
    }

    func testTamperedContentAndConfigurationHashesAreRejectedAfterDecode() throws {
        let contentTampered = try decodeMutating(RunTraceTestFixture.trace()) { object in
            object["contentHash"] = String(repeating: "0", count: 64)
        }
        XCTAssertFalse(contentTampered.isConsistent)

        let configurationTampered = try decodeMutating(RunTraceTestFixture.trace()) { object in
            object["configurationHash"] = String(repeating: "f", count: 64)
        }
        XCTAssertFalse(configurationTampered.isConsistent)
    }

    func testStageEventsStayWithinRunBoundsAndTerminalEventsFinish() {
        let run = RunTraceTestFixture.run()
        let before = RunTraceTestFixture.trace(
            run: run,
            events: [RunTraceTestFixture.event(
                startedAt: run.startedAt.addingTimeInterval(-0.1),
                finishedAt: run.startedAt)])
        XCTAssertFalse(before.isConsistent)

        let after = RunTraceTestFixture.trace(
            run: run,
            events: [RunTraceTestFixture.event(
                startedAt: run.finishedAt!.addingTimeInterval(0.1),
                finishedAt: run.finishedAt!.addingTimeInterval(0.2))])
        XCTAssertFalse(after.isConsistent)

        let reversed = RunTraceTestFixture.trace(
            run: run,
            events: [RunTraceTestFixture.event(
                startedAt: run.startedAt.addingTimeInterval(0.2),
                finishedAt: run.startedAt.addingTimeInterval(0.1))])
        XCTAssertFalse(reversed.isConsistent)

        let nilTerminal = RunTraceTestFixture.trace(
            run: run,
            events: [RunTraceTestFixture.event(
                startedAt: run.startedAt, finishedAt: nil)])
        XCTAssertFalse(nilTerminal.isConsistent)
    }

    func testRedactionRemovesPromptOutputAndErrorSummariesButRetainsFacts() throws {
        let contentTrace = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(output: "SECRET_OUTPUT"),
            sourceText: "SECRET_SOURCE", renderedInput: "SECRET_RENDERED",
            compiledPrompt: "SECRET_COMPILED",
            events: [RunTraceTestFixture.event(summary: "SECRET_EVENT")])
        let redactedContent = contentTrace.redacted()
        XCTAssertTrue(redactedContent.isRedactedTrace)
        XCTAssertNil(redactedContent.sourceText)
        XCTAssertNil(redactedContent.renderedInput)
        XCTAssertNil(redactedContent.compiledPrompt)
        XCTAssertNil(redactedContent.run.output)
        XCTAssertEqual(redactedContent.contentHash, contentTrace.contentHash)
        XCTAssertEqual(redactedContent.configurationHash, contentTrace.configurationHash)
        XCTAssertEqual(redactedContent.metrics, contentTrace.metrics)
        XCTAssertEqual(redactedContent.events.first?.summary, RunTrace.redactionMarker)
        XCTAssertTrue(redactedContent.isConsistent)

        let errorTrace = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(
                status: .failed,
                error: RunError(domain: "transport", code: 7, message: "SECRET_ERROR")),
            events: [RunTraceTestFixture.event(summary: "SECRET_ERROR_EVENT")])
        let redactedError = errorTrace.redacted()
        XCTAssertEqual(redactedError.run.error?.domain, "transport")
        XCTAssertEqual(redactedError.run.error?.code, 7)
        XCTAssertEqual(redactedError.run.error?.message, RunTrace.redactionMarker)
        XCTAssertTrue(redactedError.events.allSatisfy { $0.summary == RunTrace.redactionMarker })
        XCTAssertTrue(redactedError.isConsistent)

        let encoded = String(decoding: try redactedContent.jsonData(), as: UTF8.self)
        XCTAssertFalse(encoded.contains("SECRET_SOURCE"))
        XCTAssertFalse(encoded.contains("SECRET_RENDERED"))
        XCTAssertFalse(encoded.contains("SECRET_COMPILED"))
        XCTAssertFalse(encoded.contains("SECRET_OUTPUT"))
        XCTAssertFalse(encoded.contains("SECRET_EVENT"))
    }

    func testRedactedTraceRejectsInjectedContentOrUnredactedSummaries() throws {
        let redacted = RunTraceTestFixture.trace().redacted()
        let invalid = try decodeMutating(redacted) { object in
            object["sourceText"] = "leak"
            var run = object["run"] as? [String: Any] ?? [:]
            run["output"] = "leak"
            object["run"] = run
            var events = object["events"] as? [[String: Any]] ?? []
            if !events.isEmpty { events[0]["summary"] = "leak" }
            object["events"] = events
        }
        XCTAssertFalse(invalid.isConsistent)
    }

    private func decodeMutating(
        _ trace: RunTrace,
        mutate: (inout [String: Any]) -> Void
    ) throws -> RunTrace {
        let data = try JSONEncoder().encode(trace)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&object)
        let mutated = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(RunTrace.self, from: mutated)
    }
}
