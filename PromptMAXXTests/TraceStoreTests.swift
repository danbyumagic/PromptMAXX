import Foundation
import XCTest

@testable import PromptMAXX

@MainActor
final class TraceStoreTests: XCTestCase {
    func testLoadAppendBatchFilterDeleteAndRetentionLifecycle() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let store = context.store

        await store.loadIfNeeded()
        XCTAssertEqual(store.state, .ready)
        XCTAssertTrue(store.traces.isEmpty)

        let first = RunTraceTestFixture.trace()
        let secondRun = RunTraceTestFixture.run(
            startedAt: RunTraceTestFixture.start.addingTimeInterval(2),
            finishedAt: RunTraceTestFixture.start.addingTimeInterval(3),
            model: "other-model")
        let second = RunTraceTestFixture.trace(
            run: secondRun, kind: .evaluationCase, sourceText: "second")
        let appended = await store.append(contentsOf: [first, second])
        XCTAssertTrue(appended)
        XCTAssertEqual(store.traces.map(\.id), [first.id, second.id])

        let matches = store.filteredTraces(query: "other-model")
        XCTAssertEqual(matches.map(\.id), [second.id])
        XCTAssertEqual(store.filteredTraces(kind: .evaluationCase).map(\.id), [second.id])
        XCTAssertEqual(store.filteredTraces(from: first.startedAt, to: first.startedAt).map(\.id), [first.id])

        let deleted = await store.delete(id: second.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.traces.map(\.id), [first.id])
        let retained = await store.retain(from: first.startedAt, to: first.startedAt)
        XCTAssertTrue(retained)
        let persistedIDs = try await context.repository.load().map(\.id)
        XCTAssertEqual(persistedIDs, [first.id])
    }

    func testBatchFailureIsAtomicAndRetryPreservesCorruptStore() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let store = context.store
        let first = RunTraceTestFixture.trace()
        await store.loadIfNeeded()
        let appended = await store.append(first)
        XCTAssertTrue(appended)

        let duplicateAppend = await store.append(contentsOf: [first, RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(startedAt: RunTraceTestFixture.start.addingTimeInterval(5)))])
        XCTAssertFalse(duplicateAppend)
        XCTAssertEqual(store.traces.count, 1)
        XCTAssertEqual(store.state, .ready)
        guard case .duplicateTraceID = store.error else {
            return XCTFail("Expected duplicate ID error")
        }
        let recoveredTrace = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(startedAt: RunTraceTestFixture.start.addingTimeInterval(5)))
        let recovered = await store.append(recoveredTrace)
        XCTAssertTrue(recovered)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.traces.count, 2)

        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: context.url, options: .atomic)
        await store.retry()
        XCTAssertEqual(store.state, .failed)
        XCTAssertNotNil(store.error)
        let preservedData = try Data(contentsOf: context.url)
        XCTAssertEqual(preservedData, corruptData)
    }

    func testMissingDeleteAndInvalidRangeAreRecoverableAndVisible() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let store = context.store
        await store.loadIfNeeded()
        let first = RunTraceTestFixture.trace()
        let initialAppend = await store.append(first)
        XCTAssertTrue(initialAppend)

        let missingDelete = await store.delete(id: UUID())
        XCTAssertFalse(missingDelete)
        XCTAssertEqual(store.state, .ready)
        guard case .notFound = store.error else {
            return XCTFail("Expected typed missing-trace error")
        }

        let later = first.startedAt.addingTimeInterval(1)
        XCTAssertTrue(store.filteredTraces(from: later, to: first.startedAt).isEmpty)
        XCTAssertEqual(store.state, .ready)
        guard case .invalidDateRange = store.error else {
            return XCTFail("Expected typed invalid range error")
        }

        try await context.repository.delete(id: first.id)
        let externallyMissing = await store.delete(id: first.id)
        XCTAssertFalse(externallyMissing)
        XCTAssertEqual(store.state, .ready)
        XCTAssertTrue(store.traces.isEmpty)

        let recoveredTrace = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(startedAt: later))
        let recovered = await store.append(recoveredTrace)
        XCTAssertTrue(recovered)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.traces.count, 1)
    }

    func testMutationReloadsCanonicalRepositoryContents() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let store = context.store
        await store.loadIfNeeded()
        let external = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(model: "external"))
        try await context.repository.append(external)

        let local = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(
                startedAt: RunTraceTestFixture.start.addingTimeInterval(2), model: "local"))
        let appended = await store.append(local)
        XCTAssertTrue(appended)
        XCTAssertEqual(Set(store.traces.map(\.id)), Set([external.id, local.id]))
        let canonicalIDs = try await context.repository.load().map(\.id)
        XCTAssertEqual(canonicalIDs, store.traces.map(\.id))
    }

    func testFilteringIsLocalAndStableForEqualDates() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let store = context.store
        let first = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(model: "a-model"))
        let second = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(model: "b-model"))
        await store.loadIfNeeded()
        let appended = await store.append(contentsOf: [second, first])
        XCTAssertTrue(appended)

        let result = store.filteredTraces()
        XCTAssertEqual(result.map(\.id), [first.id, second.id].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(store.filteredTraces(status: .completed).count, 2)
    }

    func testExportsDefaultToRedactedAndCanExplicitlyRevealContent() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let store = context.store
        await store.loadIfNeeded()
        let appended = await store.append(RunTraceTestFixture.trace(
            sourceText: "PRIVATE_SOURCE", renderedInput: "PRIVATE_RENDERED",
            compiledPrompt: "PRIVATE_COMPILED"))
        XCTAssertTrue(appended)

        let redactedJSON = String(decoding: try await store.exportJSON(), as: UTF8.self)
        XCTAssertFalse(redactedJSON.contains("PRIVATE_SOURCE"))
        XCTAssertFalse(redactedJSON.contains("model output"))
        XCTAssertTrue(redactedJSON.contains(RunTrace.redactionMarker))
        let redactedMarkdown = try await store.exportMarkdown()
        XCTAssertFalse(redactedMarkdown.contains("PRIVATE_COMPILED"))

        let revealedJSON = String(decoding: try await store.exportJSON(redacted: false), as: UTF8.self)
        XCTAssertTrue(revealedJSON.contains("PRIVATE_SOURCE"))
        XCTAssertTrue(revealedJSON.contains("model output"))
    }

    func testConcurrentAppendsAreQueuedAndPersistedInOrder() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.store.loadIfNeeded()
        let first = RunTraceTestFixture.trace()
        let second = RunTraceTestFixture.trace(run: RunTraceTestFixture.run(
            startedAt: RunTraceTestFixture.start.addingTimeInterval(1),
            finishedAt: RunTraceTestFixture.start.addingTimeInterval(2)))
        async let firstResult = context.store.append(first)
        async let secondResult = context.store.append(second)
        let results = await (firstResult, secondResult)
        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        let persistedIDs = try await context.repository.load().map(\.id)
        XCTAssertEqual(persistedIDs, [first.id, second.id])
    }

    func testAppendRemainsDurableWhenCallerCancelsAfterAdmission() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.store.loadIfNeeded()
        let trace = RunTraceTestFixture.trace()

        // The store intentionally owns the serialized append task. Cancelling
        // its caller after invocation cannot retract an admitted terminal trace.
        let appendTask = Task { await context.store.append(trace) }
        await Task.yield()
        appendTask.cancel()
        let appended = await appendTask.value

        XCTAssertTrue(appended)
        XCTAssertEqual(context.store.traces.map(\.id), [trace.id])
        let persistedIDs = try await context.repository.load().map(\.id)
        XCTAssertEqual(persistedIDs, [trace.id])
    }

    private struct Context {
        let directory: URL
        let url: URL
        let repository: TraceRepository
        let store: TraceStore
    }

    private func makeContext() throws -> Context {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptMAXX-TraceStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("traces.json")
        let repository = TraceRepository(fileURL: url)
        return Context(directory: directory, url: url, repository: repository,
                       store: TraceStore(repository: repository))
    }
}
