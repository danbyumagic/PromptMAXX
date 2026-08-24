import XCTest
@testable import PromptMAXX

@MainActor
final class PromptLibraryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    private let firstDate = Date(timeIntervalSince1970: 1_800_000_000)

    private struct FixedClock: PromptLibraryClock {
        let date: Date

        func now() -> Date { date }
    }

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptMAXX-Store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        suiteName = "PromptMAXX.StoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testEmptyStartupInitializesReadyStore() async throws {
        let store = makeStore()

        await store.loadIfNeeded()

        XCTAssertEqual(store.state, .ready)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertNil(store.persistenceError)
    }

    func testLegacyMigrationUsesExactBytesAndMarksOnlyAfterSave() async throws {
        let id = UUID()
        let payload = LegacyStoreEntry(
            id: id,
            original: "legacy source",
            refined: "legacy compiled",
            createdAt: firstDate
        )
        let legacyData = try JSONEncoder().encode([payload])
        defaults.set(legacyData, forKey: PromptLibraryStore.legacyHistoryKey)
        let store = makeStore()

        await store.loadIfNeeded()

        let document = try XCTUnwrap(store.documents.first)
        XCTAssertEqual(document.id, id)
        XCTAssertEqual(document.latestRevision?.sourceText, payload.original)
        XCTAssertEqual(document.latestRevision?.compiledText, payload.refined)
        XCTAssertEqual(defaults.data(forKey: PromptLibraryStore.legacyHistoryKey), legacyData)
        XCTAssertEqual(
            defaults.integer(forKey: PromptLibraryStore.migrationMarkerKey),
            PromptLibraryStore.currentMigrationVersion
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.repository.urls.primary.path))
    }

    func testExistingLibraryTakesPrecedenceOverLegacyDefaults() async throws {
        let repository = makeRepository()
        let existing = PromptLibraryEnvelope(documents: [
            PromptDocument(
                title: "Existing",
                createdAt: firstDate,
                updatedAt: firstDate,
                revisions: [PromptRevision(revisionNumber: 1, createdAt: firstDate, sourceText: "disk")]
            )
        ])
        _ = try await repository.save(existing)
        let legacy = LegacyStoreEntry(id: UUID(), original: "legacy", refined: "", createdAt: firstDate)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: PromptLibraryStore.legacyHistoryKey)
        let store = makeStore(repository: repository)

        await store.loadIfNeeded()

        XCTAssertEqual(store.documents.map(\.title), ["Existing"])
        XCTAssertEqual(
            defaults.integer(forKey: PromptLibraryStore.migrationMarkerKey),
            PromptLibraryStore.currentMigrationVersion
        )
        XCTAssertNotNil(defaults.data(forKey: PromptLibraryStore.legacyHistoryKey))
    }

    func testCreateThenAppendPreservesIdentityAndMetadata() async throws {
        let store = makeStore()
        let spec = PromptSpec(
            title: "Spec",
            objective: "Do the work",
            outputContract: "Return Markdown",
            acceptanceCriteria: ["Has a heading"]
        )
        let profile = PromptProfile.structured

        let first = await store.saveEditor(
            documentID: nil,
            originalText: "source one",
            refinedText: "compiled one",
            spec: spec,
            profile: profile,
            modelName: "phi4-mini",
            modelVersion: "v1",
            changeSummary: "Initial save"
        )
        let firstDocument = try XCTUnwrap(first)
        let second = await store.saveEditor(
            documentID: firstDocument.id,
            originalText: "source two",
            refinedText: "compiled two",
            spec: spec,
            profile: profile,
            modelName: "phi4-mini",
            modelVersion: "v2",
            changeSummary: "Refined"
        )

        let saved = try XCTUnwrap(second)
        XCTAssertEqual(saved.id, firstDocument.id)
        XCTAssertEqual(saved.revisions.map(\.revisionNumber), [1, 2])
        XCTAssertEqual(saved.revisions.map(\.sourceText), ["source one", "source two"])
        XCTAssertEqual(saved.latestRevision?.compiledText, "compiled two")
        XCTAssertEqual(saved.latestRevision?.spec, spec)
        XCTAssertEqual(saved.latestRevision?.profileID, profile.id)
        XCTAssertEqual(saved.latestRevision?.profileVersion, profile.version)
        XCTAssertEqual(saved.latestRevision?.modelVersion, "v2")
        XCTAssertEqual(saved.latestRevision?.changeSummary, "Refined")
    }

    func testIdenticalSelectedSaveIsIdempotentAndStructuredTitleWins() async throws {
        let store = makeStore()
        let spec = PromptSpec(title: "  Structured title  ", objective: "Objective", outputContract: "Text")
        let firstResult = await awaitSave(store, documentID: nil, source: "source", spec: spec)
        let first = try XCTUnwrap(firstResult)
        let same = await store.saveEditor(
            documentID: first.id,
            originalText: "source",
            refinedText: "",
            spec: spec,
            profile: nil,
            modelName: nil
        )

        XCTAssertEqual(first.title, "Structured title")
        XCTAssertEqual(same?.revisions.count, 1)
        XCTAssertEqual(store.documents.first?.revisions.count, 1)
    }

    func testCreateAppendDeletePreservesOtherDocumentsAndRevisions() async throws {
        let store = makeStore()
        let firstResult = await store.saveEditor(
            documentID: nil,
            originalText: "first",
            refinedText: "",
            spec: nil,
            profile: nil,
            modelName: nil
        )
        let first = try XCTUnwrap(firstResult)
        let secondResult = await store.saveEditor(
            documentID: nil,
            originalText: "second",
            refinedText: "",
            spec: nil,
            profile: nil,
            modelName: nil
        )
        let second = try XCTUnwrap(secondResult)
        _ = await store.saveEditor(
            documentID: first.id,
            originalText: "first revision",
            refinedText: "",
            spec: nil,
            profile: nil,
            modelName: nil
        )

        let didDelete = await store.deleteDocument(id: second.id)
        XCTAssertTrue(didDelete)
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.documents[0].id, first.id)
        XCTAssertEqual(store.documents[0].revisions.map(\.sourceText), ["first", "first revision"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.repository.urls.backup.path))
    }

    func testCorruptLoadSurfacesFailureWithoutUsingLegacyOrOverwritingFile() async throws {
        let repository = makeRepository()
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: repository.urls.primary)
        let legacy = LegacyStoreEntry(id: UUID(), original: "legacy", refined: "", createdAt: firstDate)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: PromptLibraryStore.legacyHistoryKey)
        let store = makeStore(repository: repository)

        await store.loadIfNeeded()

        XCTAssertEqual(store.state, .failed)
        XCTAssertFalse(store.isLoading)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertNil(defaults.object(forKey: PromptLibraryStore.migrationMarkerKey))
        XCTAssertEqual(try Data(contentsOf: repository.urls.primary), corruptData)
    }

    func testMalformedLegacyPayloadLeavesStoreInFailureState() async throws {
        defaults.set(Data("not-a-legacy-array".utf8), forKey: PromptLibraryStore.legacyHistoryKey)
        let store = makeStore()

        await store.loadIfNeeded()

        XCTAssertEqual(store.state, .failed)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(defaults.integer(forKey: PromptLibraryStore.migrationMarkerKey), 0)
    }

    func testDisabledMigrationNeverReadsOrMutatesLegacyDefaults() async throws {
        let legacy = LegacyStoreEntry(
            id: UUID(), original: "private legacy value", refined: "", createdAt: firstDate)
        let legacyData = try JSONEncoder().encode([legacy])
        defaults.set(legacyData, forKey: PromptLibraryStore.legacyHistoryKey)
        let repository = makeRepository()
        let store = PromptLibraryStore(
            repository: repository,
            userDefaults: defaults,
            clock: FixedClock(date: firstDate),
            migrationEnabled: false
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.state, .ready)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertEqual(defaults.data(forKey: PromptLibraryStore.legacyHistoryKey), legacyData)
        XCTAssertNil(defaults.object(forKey: PromptLibraryStore.migrationMarkerKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.urls.primary.path))
    }

    func testSearchMatchesTitleTagsLatestSourceAndCompiledText() async throws {
        let date = firstDate
        let first = PromptDocument(
            title: "Research Notes",
            tags: ["Writing"],
            createdAt: date,
            updatedAt: date,
            revisions: [PromptRevision(revisionNumber: 1, createdAt: date, sourceText: "alpha source", compiledText: "compiled result")]
        )
        let second = PromptDocument(
            title: "Other",
            tags: ["Audio"],
            createdAt: date,
            updatedAt: date.addingTimeInterval(10),
            revisions: [PromptRevision(revisionNumber: 1, createdAt: date, sourceText: "unrelated")]
        )
        let repository = makeRepository()
        _ = try await repository.save(PromptLibraryEnvelope(documents: [first, second]))
        let store = makeStore(repository: repository)
        await store.loadIfNeeded()

        XCTAssertEqual(store.filteredHistory(search: "writing").map(\.id), [first.id])
        XCTAssertEqual(store.filteredHistory(search: "alpha").map(\.id), [first.id])
        XCTAssertEqual(store.filteredHistory(search: "COMPILED").map(\.id), [first.id])
        XCTAssertEqual(store.filteredHistory(search: "missing").count, 0)
        XCTAssertEqual(store.history.first?.id, second.id)
    }

    func testRecoveryUpdatesFailedStoreToReadyState() async throws {
        let repository = makeRepository()
        let first = PromptLibraryEnvelope(documents: [
            PromptDocument(
                title: "Recoverable",
                createdAt: firstDate,
                updatedAt: firstDate,
                revisions: [PromptRevision(revisionNumber: 1, createdAt: firstDate, sourceText: "saved")]
            )
        ])
        try await repository.save(first)
        var second = first
        second.documents[0] = try second.documents[0].appending(
            PromptRevision(revisionNumber: 2, createdAt: firstDate, sourceText: "newer")
        )
        try await repository.save(second)
        try Data("corrupt".utf8).write(to: repository.urls.primary)
        let store = makeStore(repository: repository)

        await store.loadIfNeeded()
        XCTAssertEqual(store.state, .failed)
        let recovered = await store.recoverBackup()
        XCTAssertTrue(recovered)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.documents.first?.latestRevision?.sourceText, "saved")
    }

    func testTwoStoresAppendAgainstOneRepositoryWithoutCollidingRevisionNumbers() async throws {
        let repository = makeRepository()
        let initial = PromptDocument(
            title: "Shared",
            createdAt: firstDate,
            updatedAt: firstDate,
            revisions: [PromptRevision(revisionNumber: 1, createdAt: firstDate, sourceText: "base")]
        )
        _ = try await repository.save(PromptLibraryEnvelope(documents: [initial]))
        let firstStore = makeStore(repository: repository)
        let secondStore = makeStore(repository: repository)
        await firstStore.loadIfNeeded()
        await secondStore.loadIfNeeded()

        async let firstAppend = firstStore.saveEditor(
            documentID: initial.id,
            originalText: "first window",
            refinedText: "",
            spec: nil,
            profile: nil,
            modelName: nil
        )
        async let secondAppend = secondStore.saveEditor(
            documentID: initial.id,
            originalText: "second window",
            refinedText: "",
            spec: nil,
            profile: nil,
            modelName: nil
        )
        let results = await (firstAppend, secondAppend)

        XCTAssertNotNil(results.0)
        XCTAssertNotNil(results.1)
        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded.documents[0].revisions.map(\.revisionNumber), [1, 2, 3])
        XCTAssertEqual(reloaded.documents[0].revisions.first?.sourceText, "base")
        XCTAssertEqual(
            reloaded.documents[0].revisions.dropFirst().map(\.sourceText).sorted(),
            ["first window", "second window"]
        )
    }

    private func makeRepository() -> PromptLibraryRepository {
        PromptLibraryRepository(fileURL: temporaryDirectory.appendingPathComponent("prompt-library.json"))
    }

    private func makeStore(repository: PromptLibraryRepository? = nil) -> PromptLibraryStore {
        PromptLibraryStore(
            repository: repository ?? makeRepository(),
            userDefaults: defaults,
            clock: FixedClock(date: firstDate)
        )
    }

    private func awaitSave(
        _ store: PromptLibraryStore,
        documentID: UUID?,
        source: String,
        spec: PromptSpec?
    ) async -> PromptDocument? {
        await store.saveEditor(
            documentID: documentID,
            originalText: source,
            refinedText: "",
            spec: spec,
            profile: nil,
            modelName: nil
        )
    }
}

private struct LegacyStoreEntry: Codable {
    let id: UUID
    let original: String
    let refined: String
    let createdAt: Date
}
