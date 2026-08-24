import Foundation
import XCTest

@testable import PromptMAXX

final class TraceRepositoryTests: XCTestCase {
    func testAppendLoadOrderFilterRangeAndIsolatedCleanup() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let first = RunTraceTestFixture.trace()
        let secondRun = RunTraceTestFixture.run(
            startedAt: RunTraceTestFixture.start.addingTimeInterval(2),
            finishedAt: RunTraceTestFixture.start.addingTimeInterval(3),
            model: "other")
        let second = RunTraceTestFixture.trace(
            run: secondRun, kind: .evaluationCase, sourceText: "b",
            events: [RunTraceTestFixture.event(
                startedAt: secondRun.startedAt,
                finishedAt: secondRun.startedAt.addingTimeInterval(0.1))])
        let repo = context.repository

        try await repo.append(first)
        try await repo.append(second)
        let ordered = try await repo.load().map(\.id)
        XCTAssertEqual(ordered, [first.id, second.id])

        let filtered = try await repo.filter(kind: .evaluationCase)
        XCTAssertEqual(filtered.map(\.id), [second.id])
        let inclusive = try await repo.filter(
            from: first.startedAt, to: second.startedAt)
        XCTAssertEqual(inclusive.map(\.id), [first.id, second.id])
        let middle = try await repo.filter(
            from: first.startedAt.addingTimeInterval(0.1),
            to: second.startedAt.addingTimeInterval(-0.1))
        XCTAssertTrue(middle.isEmpty)

        try await repo.retain(from: first.startedAt, to: first.startedAt)
        let retained = try await repo.load()
        XCTAssertEqual(retained.map(\.id), [first.id])
    }

    func testRejectsDuplicateAppendAndDeleteMissingID() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let repo = context.repository
        let trace = RunTraceTestFixture.trace()
        try await repo.append(trace)

        do {
            try await repo.append(trace)
            XCTFail("Expected duplicate trace ID")
        } catch let error as TraceRepositoryError {
            guard case .duplicateTraceID(trace.id) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let missingID = UUID()
        do {
            try await repo.delete(id: missingID)
            XCTFail("Expected missing trace error")
        } catch let error as TraceRepositoryError {
            guard case .notFound = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsInvalidDateRange() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let repo = context.repository
        let from = RunTraceTestFixture.start.addingTimeInterval(2)
        let to = RunTraceTestFixture.start.addingTimeInterval(1)

        do {
            _ = try await repo.filter(from: from, to: to)
            XCTFail("Expected invalid date range")
        } catch let error as TraceRepositoryError {
            guard case .invalidDateRange = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLoadValidatesVersionTraceConsistencyAndDuplicateIDs() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let trace = RunTraceTestFixture.trace()

        try writeEnvelope(TraceEnvelope(version: TraceEnvelope.currentVersion + 1, traces: [trace]), to: context.url)
        do {
            try await context.repository.append(trace)
            XCTFail("Expected unsupported version")
        } catch let error as TraceRepositoryError {
            guard case .unsupportedVersion = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let unsupportedData = try Data(contentsOf: context.url)
        let unsupportedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: unsupportedData) as? [String: Any])
        XCTAssertEqual(unsupportedObject["version"] as? Int, TraceEnvelope.currentVersion + 1)

        try writeEnvelope(TraceEnvelope(traces: [trace, trace]), to: context.url)
        do {
            _ = try await context.repository.load()
            XCTFail("Expected duplicate ID")
        } catch let error as TraceRepositoryError {
            guard case .duplicateTraceID(trace.id) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        // Mutate an otherwise JSON-encodable trace so validation is exercised
        // after decoding (JSONEncoder intentionally rejects non-finite numbers).
        var tamperedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder.traceData(trace),
                options: [.fragmentsAllowed]) as? [String: Any])
        tamperedObject["contentHash"] = String(repeating: "0", count: 64)
        try JSONSerialization.data(withJSONObject: [
            "version": TraceEnvelope.currentVersion,
            "traces": [tamperedObject]
        ], options: [.prettyPrinted, .sortedKeys]).write(to: context.url, options: .atomic)
        do {
            _ = try await context.repository.load()
            XCTFail("Expected invalid trace envelope")
        } catch let error as TraceRepositoryError {
            guard case .invalidEnvelope = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMutationsDoNotOverwriteCorruptStoreAndReadWriteErrorsAreTyped() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let repo = context.repository
        try Data("not json".utf8).write(to: context.url)
        do {
            try await repo.append(RunTraceTestFixture.trace())
            XCTFail("Expected corrupt store")
        } catch let error as TraceRepositoryError {
            guard case .corrupt = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let preservedCorruptContents = try String(contentsOf: context.url, encoding: .utf8)
        XCTAssertEqual(preservedCorruptContents, "not json")

        let unreadableURL = context.directory.appendingPathComponent("directory-as-file")
        try FileManager.default.createDirectory(at: unreadableURL, withIntermediateDirectories: true)
        do {
            _ = try await TraceRepository(fileURL: unreadableURL).load()
            XCTFail("Expected read failure")
        } catch let error as TraceRepositoryError {
            guard case .readFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let blockedParent = context.directory.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blockedParent)
        let blockedRepo = TraceRepository(fileURL: blockedParent.appendingPathComponent("traces.json"))
        do {
            try await blockedRepo.append(RunTraceTestFixture.trace())
            XCTFail("Expected directory creation failure")
        } catch let error as TraceRepositoryError {
            guard case .directoryCreationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDeterministicJSONAndMarkdownEnvelopeExportsSupportRedaction() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let repo = context.repository
        try await repo.append(RunTraceTestFixture.trace(
            sourceText: "PRIVATE_SOURCE", renderedInput: "PRIVATE_RENDERED",
            compiledPrompt: "PRIVATE_COMPILED"))

        let first = try await repo.exportJSON()
        let second = try await repo.exportJSON()
        XCTAssertEqual(first, second)
        let json = String(decoding: first, as: UTF8.self)
        XCTAssertTrue(json.contains("\n  \"traces\""))
        XCTAssertTrue(json.contains("\"version\" : 1") || json.contains("\"version\": 1"))

        let markdown = try await repo.exportMarkdown(redacted: true)
        XCTAssertTrue(markdown.contains("# Trace Envelope"))
        XCTAssertTrue(markdown.contains("Redacted: true"))
        XCTAssertFalse(markdown.contains("PRIVATE_SOURCE"))
        XCTAssertFalse(markdown.contains("PRIVATE_RENDERED"))
        XCTAssertFalse(markdown.contains("PRIVATE_COMPILED"))
        XCTAssertTrue(markdown.contains("Content hash"))
    }

    func testMarkdownExportContainsCompleteFactsAndSafelyRedactsContent() async throws {
        let context = try makeRepository()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let failedRun = RunTraceTestFixture.run(
            status: .failed,
            error: RunError(domain: "PRIVATE_DOMAIN", code: 42, message: "PRIVATE_ERROR"))
        let trace = RunTraceTestFixture.trace(
            run: failedRun,
            sourceText: "PRIVATE_SOURCE",
            renderedInput: "PRIVATE_RENDERED",
            compiledPrompt: "PRIVATE_COMPILED",
            generationOptions: PromptGenerationOptions(
                temperature: 0.2, topP: 0.8, maxTokens: 128, stream: true),
            events: [RunTraceTestFixture.event(summary: "PRIVATE_EVENT with ``` fence")])
        try await context.repository.append(trace)

        let markdown = try await context.repository.exportMarkdown(redacted: false)
        XCTAssertTrue(markdown.contains("Provider:"))
        XCTAssertTrue(markdown.contains("Model version:"))
        XCTAssertTrue(markdown.contains("Configuration hash:"))
        XCTAssertTrue(markdown.contains("Status: `failed`"))
        XCTAssertTrue(markdown.contains("Started:"))
        XCTAssertTrue(markdown.contains("Finished:"))
        XCTAssertTrue(markdown.contains("TTFT milliseconds:"))
        XCTAssertTrue(markdown.contains("Input tokens:"))
        XCTAssertTrue(markdown.contains("Retries:"))
        XCTAssertTrue(markdown.contains("Validation issues:"))
        XCTAssertTrue(markdown.contains("PRIVATE_DOMAIN"))
        XCTAssertTrue(markdown.contains("PRIVATE_ERROR"))
        XCTAssertTrue(markdown.contains("PRIVATE_EVENT"))
        XCTAssertTrue(markdown.contains("PRIVATE_SOURCE"))
        XCTAssertTrue(markdown.contains("PRIVATE_RENDERED"))
        XCTAssertTrue(markdown.contains("PRIVATE_COMPILED"))
        XCTAssertTrue(markdown.contains("``\u{200B}`"))

        let redacted = try await context.repository.exportMarkdown(redacted: true)
        XCTAssertFalse(redacted.contains("PRIVATE_DOMAIN"))
        XCTAssertFalse(redacted.contains("PRIVATE_ERROR"))
        XCTAssertFalse(redacted.contains("PRIVATE_EVENT"))
        XCTAssertFalse(redacted.contains("PRIVATE_SOURCE"))
        XCTAssertFalse(redacted.contains("PRIVATE_RENDERED"))
        XCTAssertFalse(redacted.contains("PRIVATE_COMPILED"))
        XCTAssertTrue(redacted.contains(RunTrace.redactionMarker))
    }

    private struct RepositoryContext {
        let directory: URL
        let url: URL
        let repository: TraceRepository
    }

    private func makeRepository() throws -> RepositoryContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptMAXX-TraceRepository-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("traces.json")
        return RepositoryContext(directory: directory, url: url, repository: TraceRepository(fileURL: url))
    }

    private func writeEnvelope(_ envelope: TraceEnvelope, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static func traceData(_ trace: RunTrace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(trace)
    }
}
