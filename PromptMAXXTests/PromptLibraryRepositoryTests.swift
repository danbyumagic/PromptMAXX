import XCTest
@testable import PromptMAXX

final class PromptLibraryRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptMAXX-Persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRoundTripNormalizesAndReloadsPortableLibrary() async throws {
        let repository = makeRepository()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let revision = PromptRevision(
            revisionNumber: 1,
            name: "  First revision ",
            createdAt: date,
            sourceText: "  Write a useful answer\n\n    ```swift\n    let value = 1\n    ```  ",
            compiledText: "  Write a useful answer\n\n    Keep this indentation.  "
        )
        let document = PromptDocument(
            title: "  A prompt  ",
            tags: ["writing", " writing ", "research"],
            createdAt: date,
            updatedAt: date,
            revisions: [revision]
        )

        let saved = try await repository.save(PromptLibraryEnvelope(documents: [document]))
        let loaded = try await repository.load()

        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded.documents[0].title, "A prompt")
        XCTAssertEqual(loaded.documents[0].tags, ["writing", "research"])
        XCTAssertEqual(loaded.documents[0].revisions[0].sourceText, "Write a useful answer\n\n    ```swift\n    let value = 1\n    ```")
        XCTAssertEqual(loaded.documents[0].revisions[0].compiledText, "Write a useful answer\n\n    Keep this indentation.")
    }

    func testAppendRevisionRetainsPriorHistoryAndRequiresNextNumber() async throws {
        let repository = makeRepository()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let document = PromptDocument(
            title: "History",
            createdAt: date,
            updatedAt: date,
            revisions: [PromptRevision(revisionNumber: 1, createdAt: date, sourceText: "one")]
        )
        let library = try await repository.save(PromptLibraryEnvelope(documents: [document]))
        let id = try XCTUnwrap(library.documents.first?.id)

        let appended = try await repository.appendRevision(
            PromptRevision(revisionNumber: 2, createdAt: date.addingTimeInterval(1), sourceText: "two"),
            to: id
        )
        XCTAssertEqual(appended.documents[0].revisions.map(\.sourceText), ["one", "two"])

        do {
            _ = try document.appending(PromptRevision(revisionNumber: 3, createdAt: date, sourceText: "three"))
            XCTFail("Expected an invalid revision number")
        } catch let error as PromptDocumentError {
            XCTAssertEqual(error, .invalidRevisionNumber(expected: 2, actual: 3))
        }
    }

    func testValidationRejectsEmptyDocumentsAndNonContiguousRevisions() {
        let invalid = PromptLibraryEnvelope(documents: [
            PromptDocument(
                title: "Invalid",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 9),
                revisions: [PromptRevision(revisionNumber: 2, sourceText: "text")]
            )
        ])

        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(invalid.validationIssues.contains { $0.path == "documents[0].updatedAt" })
        XCTAssertTrue(invalid.validationIssues.contains { $0.path == "documents[0].revisions[0].revisionNumber" })
    }

    func testLegacyArrayMigratesWithoutPromptEntryDependency() async throws {
        let repository = makeRepository()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_100)
        let legacy: [[String: Any]] = [[
            "id": id.uuidString,
            "original": "  Original request  ",
            "refined": "  Refined request  ",
            "createdAt": ISO8601DateFormatter().string(from: date)
        ]]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        try data.write(to: repository.urls.primary)

        let loaded = try await repository.load()
        XCTAssertEqual(loaded.documents.count, 1)
        XCTAssertEqual(loaded.documents[0].id, id)
        XCTAssertEqual(loaded.documents[0].revisions[0].sourceText, "Original request")
        XCTAssertEqual(loaded.documents[0].revisions[0].compiledText, "Refined request")
        XCTAssertEqual(loaded.documents[0].revisions[0].changeSummary, "Migrated from legacy prompt history")
    }

    func testAtomicSaveCreatesBackupAndReloadsLatestVersion() async throws {
        let repository = makeRepository()
        let first = makeLibrary(source: "first")
        try await repository.save(first)
        var second = first
        let documentID = try XCTUnwrap(second.documents.first?.id)
        let revision = PromptRevision(
            revisionNumber: 2,
            createdAt: Date(timeIntervalSince1970: 1_700_000_001),
            sourceText: "second"
        )
        second.documents[0] = try second.documents[0].appending(revision)
        XCTAssertEqual(second.documents[0].id, documentID)
        try await repository.save(second)

        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.urls.backup.path))
        let loaded = try await repository.load()
        XCTAssertEqual(loaded.documents[0].revisions.map(\.sourceText), ["first", "second"])
        let temporaryFiles = try FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".tmp") }
        XCTAssertTrue(temporaryFiles.isEmpty)
    }

    func testLegacyNumericDatePayloadMigratesExactlyLikePromptStore() async throws {
        let repository = makeRepository()
        let id = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 123_456)
        let encoder = JSONEncoder()
        // No date strategy: this is the exact legacy PromptStore encoding.
        let payload = LegacyEntryForTest(id: id, original: "Original", refined: "Refined", createdAt: date)
        try encoder.encode([payload]).write(to: repository.urls.primary)

        let loaded = try await repository.load()
        XCTAssertEqual(loaded.documents[0].id, id)
        XCTAssertEqual(loaded.documents[0].createdAt, date)
        XCTAssertEqual(loaded.documents[0].revisions[0].createdAt, date)
    }

    func testSaveRejectsRevisionMutationDeletionAndReordering() async throws {
        let repository = makeRepository()
        let first = makeLibrary(source: "one")
        try await repository.save(first)
        let document = try XCTUnwrap(first.documents.first)
        let secondRevision = PromptRevision(revisionNumber: 2, createdAt: document.createdAt, sourceText: "two")

        var mutated = first
        mutated.documents[0].revisions[0].sourceText = "edited"
        try await assertAppendOnlyViolation(repository, library: mutated)

        var deleted = first
        deleted.documents[0].revisions = []
        try await assertAppendOnlyViolation(repository, library: deleted)

        var reordered = first
        reordered.documents[0] = try document.appending(secondRevision)
        reordered.documents[0].revisions.reverse()
        try await assertAppendOnlyViolation(repository, library: reordered)
    }

    func testExplicitDeleteRemovesOnlyRequestedDocumentAndKeepsBackup() async throws {
        let repository = makeRepository()
        let first = makeLibrary(source: "first").documents[0]
        var second = makeLibrary(source: "second").documents[0]
        second.revisions = [
            PromptRevision(revisionNumber: 1, createdAt: second.createdAt, sourceText: "second"),
            PromptRevision(revisionNumber: 2, createdAt: second.createdAt, sourceText: "second revision")
        ]
        second.updatedAt = second.createdAt
        let library = PromptLibraryEnvelope(documents: [first, second])
        try await repository.save(library)

        let deleted = try await repository.deleteDocument(id: first.id)
        XCTAssertEqual(deleted.documents.map(\.id), [second.id])
        XCTAssertEqual(deleted.documents[0].revisions.map(\.sourceText), ["second", "second revision"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.urls.backup.path))

        let backup = try await repository.importFile(from: repository.urls.backup)
        XCTAssertEqual(Set(backup.documents.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(backup.documents.first(where: { $0.id == second.id })?.revisions.count, 2)
    }

    func testExplicitDeleteReportsMissingDocumentWithoutChangingStore() async throws {
        let repository = makeRepository()
        let library = makeLibrary(source: "keep")
        try await repository.save(library)
        let missingID = UUID()

        do {
            _ = try await repository.deleteDocument(id: missingID)
            XCTFail("Expected missing document error")
        } catch let error as PromptLibraryError {
            guard case .documentNotFound(missingID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, library.normalized)
    }

    func testRevisionTimestampBoundsAndCaseInsensitiveTagsAreValidated() {
        let created = Date(timeIntervalSince1970: 100)
        let updated = Date(timeIntervalSince1970: 200)
        let invalid = PromptDocument(
            title: "Tags",
            tags: ["Swift", " swift ", "SWIFT", "Code"],
            createdAt: created,
            updatedAt: updated,
            revisions: [
                PromptRevision(revisionNumber: 1, createdAt: Date(timeIntervalSince1970: 150), sourceText: "one"),
                PromptRevision(revisionNumber: 2, createdAt: Date(timeIntervalSince1970: 120), sourceText: "two"),
                PromptRevision(revisionNumber: 3, createdAt: Date(timeIntervalSince1970: 250), sourceText: "three")
            ]
        )

        XCTAssertEqual(invalid.normalized.tags, ["Swift", "Code"])
        XCTAssertTrue(invalid.validationIssues.contains { $0.message.contains("nondecreasing") })
        XCTAssertTrue(invalid.validationIssues.contains { $0.message.contains("within the document") })
    }

    func testCorruptPrimaryIsPreservedAndExplicitRecoveryUsesBackup() async throws {
        let repository = makeRepository()
        let first = makeLibrary(source: "recoverable")
        try await repository.save(first)
        var newer = first
        newer.documents[0] = try newer.documents[0].appending(
            PromptRevision(
                revisionNumber: 2,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001),
                sourceText: "newer"
            )
        )
        try await repository.save(newer)
        try Data("not json".utf8).write(to: repository.urls.primary)

        do {
            _ = try await repository.load()
            XCTFail("Expected corrupt store error")
        } catch let error as PromptLibraryError {
            guard case .corruptStore = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let recovered = try await repository.recoverFromBackup()
        XCTAssertEqual(recovered.documents[0].revisions[0].sourceText, "recoverable")
        let quarantined = try FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt-") }
        XCTAssertEqual(quarantined.count, 1)
    }

    func testImportRejectsMalformedOrInvalidLibrariesWithoutWriting() async throws {
        let repository = makeRepository()
        do {
            _ = try await repository.importData(Data("{ definitely not json }".utf8))
            XCTFail("Expected import rejection")
        } catch let error as PromptLibraryError {
            guard case .importRejected = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.urls.primary.path))

        let invalid = PromptLibraryEnvelope(formatVersion: 99)
        let encoder = JSONEncoder()
        let invalidData = try encoder.encode(invalid)
        do {
            _ = try await repository.importData(invalidData)
            XCTFail("Expected unsupported format rejection")
        } catch let error as PromptLibraryError {
            guard case .importRejected = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testFavoriteMetadataTransactionDoesNotMutateRevisions() async throws {
        let repository = makeRepository()
        let library = makeLibrary(source: "favorite")
        try await repository.save(library)
        let before = try await repository.load()
        let id = try XCTUnwrap(library.documents.first?.id)

        let favorited = try await repository.setFavorite(true, for: id)

        XCTAssertTrue(favorited.documents[0].isFavorite)
        XCTAssertEqual(favorited.documents[0].revisions, before.documents[0].revisions)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.urls.backup.path))
    }

    func testMergeAddsNewAndIdenticalDocumentsWithoutDuplication() async throws {
        let repository = makeRepository()
        let local = makeLibrary(source: "local")
        try await repository.save(local)
        let imported = PromptLibraryEnvelope(documents: [
            local.documents[0],
            PromptDocument(
                title: "Imported",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                revisions: [PromptRevision(revisionNumber: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000), sourceText: "new")]
            )
        ])

        let merged = try await repository.merge(imported)
        let repeated = try await repository.merge(imported)

        XCTAssertEqual(merged.documents.count, 2)
        XCTAssertEqual(repeated.documents.count, 2)
        XCTAssertEqual(Set(repeated.documents.map(\.title)), ["Test", "Imported"])
    }

    func testMergePrefixChoosesLongerHistoryAndMetadata() async throws {
        let repository = makeRepository()
        let base = makeLibrary(source: "one")
        try await repository.save(base)
        let id = try XCTUnwrap(base.documents.first?.id)
        let date = Date(timeIntervalSince1970: 1_700_000_010)
        let longerRevision = PromptRevision(revisionNumber: 2, createdAt: date, sourceText: "two")
        var importedLongerDocument = base.documents[0]
        importedLongerDocument.title = "Imported newer"
        importedLongerDocument.updatedAt = date
        importedLongerDocument.revisions.append(longerRevision)
        let importedLonger = PromptLibraryEnvelope(documents: [importedLongerDocument])

        let advanced = try await repository.merge(importedLonger)
        XCTAssertEqual(advanced.documents.first?.id, id)
        XCTAssertEqual(advanced.documents.first?.title, "Imported newer")
        XCTAssertEqual(advanced.documents.first?.revisions.map(\.sourceText), ["one", "two"])

        let localAhead = try await repository.merge(base)
        XCTAssertEqual(localAhead.documents.first?.revisions.map(\.sourceText), ["one", "two"])
    }

    func testMergeDivergenceRejectsEntireImportWithoutChangingPrimary() async throws {
        let repository = makeRepository()
        let local = makeLibrary(source: "local")
        try await repository.save(local)
        let before = try Data(contentsOf: repository.urls.primary)
        var divergentDocument = local.documents[0]
        divergentDocument.revisions[0].sourceText = "different"

        do {
            _ = try await repository.merge(PromptLibraryEnvelope(documents: [divergentDocument]))
            XCTFail("Expected a merge conflict")
        } catch let error as PromptLibraryError {
            guard case .mergeConflict = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: repository.urls.primary), before)
    }

    func testExportAndImportRoundTripUsesPortablePrettyJSON() async throws {
        let repository = makeRepository()
        let library = makeLibrary(source: "portable")
        let data = try await repository.exportData(library)
        let imported = try await repository.importData(data)

        XCTAssertEqual(imported, library.normalized)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\n"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("T"))
    }

    private func makeRepository() -> PromptLibraryRepository {
        PromptLibraryRepository(fileURL: temporaryDirectory.appendingPathComponent("library.json"))
    }

    private func makeLibrary(source: String) -> PromptLibraryEnvelope {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return PromptLibraryEnvelope(documents: [
            PromptDocument(
                title: "Test",
                createdAt: date,
                updatedAt: date,
                revisions: [PromptRevision(revisionNumber: 1, createdAt: date, sourceText: source)]
            )
        ])
    }

    private func assertAppendOnlyViolation(
        _ repository: PromptLibraryRepository,
        library: PromptLibraryEnvelope
    ) async throws {
        do {
            _ = try await repository.save(library)
            XCTFail("Expected append-only violation")
        } catch let error as PromptLibraryError {
            guard case .appendOnlyViolation = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }
}

private struct LegacyEntryForTest: Codable {
    let id: UUID
    let original: String
    let refined: String
    let createdAt: Date
}
