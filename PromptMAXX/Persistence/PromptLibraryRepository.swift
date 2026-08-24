//
//  PromptLibraryRepository.swift
//  PromptMAXX
//
//  An actor-isolated JSON repository. The file on disk is never replaced when
//  it cannot be decoded; callers can inspect or recover the previous backup.
//

import Foundation

nonisolated public enum PromptLibraryError: Error, LocalizedError, Hashable, Sendable {
    case fileNotFound(URL)
    case invalidFileURL
    case validationFailed([PromptLibraryValidationIssue])
    case corruptStore(URL, reason: String)
    case existingStoreUnreadable(URL, reason: String)
    case backupUnavailable(URL)
    case backupFailed(URL, reason: String)
    case writeFailed(URL, reason: String)
    case importRejected(reason: String)
    case unsupportedFormat(Int)
    case appendOnlyViolation(path: String, reason: String)
    case documentNotFound(UUID)
    case mergeConflict(UUID, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(url): return "Prompt library not found at \(url.path)."
        case .invalidFileURL: return "The prompt library URL is invalid."
        case let .validationFailed(issues): return "Prompt library validation failed: \(issues.map(\.message).joined(separator: "; "))."
        case let .corruptStore(url, reason): return "Prompt library at \(url.path) is unreadable: \(reason)."
        case let .existingStoreUnreadable(url, reason): return "Refusing to overwrite unreadable prompt library at \(url.path): \(reason)."
        case let .backupUnavailable(url): return "No recoverable prompt library backup exists at \(url.path)."
        case let .backupFailed(url, reason): return "Could not create the prompt library backup at \(url.path): \(reason)."
        case let .writeFailed(url, reason): return "Could not write the prompt library at \(url.path): \(reason)."
        case let .importRejected(reason): return "Prompt library import rejected: \(reason)."
        case let .unsupportedFormat(version): return "Unsupported prompt library format version \(version)."
        case let .appendOnlyViolation(path, reason): return "Append-only history violation at \(path): \(reason)."
        case let .documentNotFound(id): return "Prompt document \(id.uuidString) was not found."
        case let .mergeConflict(id, reason): return "Cannot merge prompt document \(id.uuidString): \(reason)"
        }
    }
}

nonisolated public struct PromptLibraryRepositoryURLs: Hashable, Sendable {
    public let primary: URL
    public let backup: URL

    public init(primary: URL, backup: URL) {
        self.primary = primary
        self.backup = backup
    }
}

public actor PromptLibraryRepository {
    public nonisolated let urls: PromptLibraryRepositoryURLs

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let legacyDecoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.urls = PromptLibraryRepositoryURLs(
            primary: fileURL,
            backup: fileURL.appendingPathExtension("bak")
        )
        self.fileManager = fileManager
        self.encoder = Self.makeEncoder()
        self.decoder = Self.makeDecoder()
        self.legacyDecoder = Self.makeLegacyDecoder()
    }

    /// Returns the conventional Application Support location without creating
    /// it. Tests and previews should inject their own temporary URL instead.
    public static func defaultFileURL(
        applicationName: String = "PromptMAXX",
        fileManager: FileManager = .default
    ) throws -> URL {
        guard !applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            throw PromptLibraryError.invalidFileURL
        }
        return base.appendingPathComponent(applicationName, isDirectory: true)
            .appendingPathComponent("prompt-library.json", isDirectory: false)
    }

    public func load() throws -> PromptLibraryEnvelope {
        guard fileManager.fileExists(atPath: urls.primary.path) else {
            throw PromptLibraryError.fileNotFound(urls.primary)
        }
        let data: Data
        do {
            data = try Data(contentsOf: urls.primary)
        } catch {
            throw PromptLibraryError.corruptStore(urls.primary, reason: error.localizedDescription)
        }
        return try decode(data, sourceURL: urls.primary)
    }

    /// Loads and validates the current file, then atomically persists its
    /// normalized representation. Existing readable legacy arrays are migrated
    /// on save; corrupt files are rejected before any replacement is attempted.
    @discardableResult
    public func save(_ library: PromptLibraryEnvelope) throws -> PromptLibraryEnvelope {
        let normalized = library.normalized
        if fileManager.fileExists(atPath: urls.primary.path) {
            let existingData: Data
            do {
                existingData = try Data(contentsOf: urls.primary)
            } catch let error as PromptLibraryError {
                throw PromptLibraryError.existingStoreUnreadable(urls.primary, reason: error.localizedDescription)
            } catch {
                throw PromptLibraryError.existingStoreUnreadable(urls.primary, reason: error.localizedDescription)
            }
            do {
                let existing = try decodeModern(existingData, sourceURL: urls.primary)
                try enforceAppendOnly(existing: existing, proposed: normalized)
            } catch let error as PromptLibraryError {
                if case .appendOnlyViolation = error {
                    throw error
                }
                // A readable legacy array is upgradeable and has no revision
                // history contract to compare against yet. Any other decode
                // failure is rejected before the primary file is touched.
                do {
                    _ = try decode(existingData, sourceURL: urls.primary)
                } catch {
                    throw PromptLibraryError.existingStoreUnreadable(urls.primary, reason: error.localizedDescription)
                }
            } catch {
                do {
                    _ = try decode(existingData, sourceURL: urls.primary)
                } catch {
                    throw PromptLibraryError.existingStoreUnreadable(urls.primary, reason: error.localizedDescription)
                }
            }
        }
        let validated = try normalized.validatingNormalized()
        if fileManager.fileExists(atPath: urls.primary.path) {
            try makeBackup()
        }
        try writeAtomically(validated, to: urls.primary, protectUnreadable: false)
        return validated
    }

    /// Appends exactly one new revision to an existing document. There is no
    /// update-in-place revision operation, preserving the audit trail.
    @discardableResult
    public func appendRevision(
        _ revision: PromptRevision,
        to documentID: UUID
    ) throws -> PromptLibraryEnvelope {
        var library = try load()
        guard let index = library.documents.firstIndex(where: { $0.id == documentID }) else {
            throw PromptLibraryError.documentNotFound(documentID)
        }
        do {
            library.documents[index] = try library.documents[index].appending(revision)
        } catch {
            throw PromptLibraryError.validationFailed([
                .init(path: "documents[\(index)].revisions", message: error.localizedDescription)
            ])
        }
        return try save(library)
    }

    /// Appends a revision while assigning its number from the repository's
    /// current state. The read, number assignment, append, and atomic write
    /// all occur within this actor transaction, so stale windows cannot race
    /// one another into the same revision number.
    @discardableResult
    public func appendRevisionAssigningNextNumber(
        _ revision: PromptRevision,
        to documentID: UUID
    ) throws -> PromptLibraryEnvelope {
        var library = try load()
        guard let index = library.documents.firstIndex(where: { $0.id == documentID }) else {
            throw PromptLibraryError.documentNotFound(documentID)
        }
        let nextNumber = (library.documents[index].revisions.last?.revisionNumber ?? 0) + 1
        let assigned = PromptRevision(
            id: revision.id,
            revisionNumber: nextNumber,
            name: revision.name.isEmpty ? "Revision \(nextNumber)" : revision.name,
            createdAt: revision.createdAt,
            sourceText: revision.sourceText,
            spec: revision.spec,
            compiledText: revision.compiledText,
            changeSummary: revision.changeSummary,
            schemaVersion: revision.schemaVersion,
            profileID: revision.profileID,
            profileVersion: revision.profileVersion,
            modelName: revision.modelName,
            modelVersion: revision.modelVersion
        )
        do {
            library.documents[index] = try library.documents[index].appending(assigned)
        } catch {
            throw PromptLibraryError.validationFailed([
                .init(path: "documents[\(index)].revisions", message: error.localizedDescription)
            ])
        }
        return try save(library)
    }

    /// Creates one document as an atomic repository transaction. The actor
    /// serializes the load/modify/save sequence for multi-window callers.
    @discardableResult
    public func createDocument(_ document: PromptDocument) throws -> PromptLibraryEnvelope {
        var library: PromptLibraryEnvelope
        if fileManager.fileExists(atPath: urls.primary.path) {
            library = try load()
        } else {
            library = PromptLibraryEnvelope()
        }
        guard !library.documents.contains(where: { $0.id == document.id }) else {
            throw PromptLibraryError.validationFailed([
                .init(path: "documents", message: "Document \(document.id.uuidString) already exists.")
            ])
        }
        library.documents.append(document)
        return try save(library)
    }

    @discardableResult
    public func setFavorite(_ favorite: Bool, for documentID: UUID) throws -> PromptLibraryEnvelope {
        var library = try load()
        guard let index = library.documents.firstIndex(where: { $0.id == documentID }) else {
            throw PromptLibraryError.documentNotFound(documentID)
        }
        library.documents[index].isFavorite = favorite
        return try saveMetadata(library)
    }

    /// Merges a validated portable library without replacing the current
    /// store. New IDs are added, identical documents are ignored, and a
    /// strict revision-prefix match keeps the longer valid history. Divergent
    /// histories reject the complete merge before any write occurs.
    @discardableResult
    public func merge(_ imported: PromptLibraryEnvelope) throws -> PromptLibraryEnvelope {
        let incoming = try imported.validatingNormalized()
        let existing = fileManager.fileExists(atPath: urls.primary.path)
            ? try load()
            : PromptLibraryEnvelope()
        var merged = existing
        for importedDocument in incoming.documents {
            guard let index = merged.documents.firstIndex(where: { $0.id == importedDocument.id }) else {
                merged.documents.append(importedDocument)
                continue
            }
            let localDocument = merged.documents[index]
            let localRevisions = localDocument.revisions
            let importedRevisions = importedDocument.revisions
            let localIsPrefix = importedRevisions.count >= localRevisions.count &&
                Array(importedRevisions.prefix(localRevisions.count)) == localRevisions
            let importedIsPrefix = localRevisions.count >= importedRevisions.count &&
                Array(localRevisions.prefix(importedRevisions.count)) == importedRevisions
            guard localIsPrefix || importedIsPrefix else {
                throw PromptLibraryError.mergeConflict(
                    importedDocument.id,
                    reason: "revision histories diverge; import was rejected without changes"
                )
            }
            if localIsPrefix && importedIsPrefix {
                if importedDocument == localDocument { continue }
                if importedDocument.updatedAt >= localDocument.updatedAt {
                    merged.documents[index] = importedDocument
                }
            } else if localIsPrefix {
                merged.documents[index] = importedDocument
            }
        }
        return try saveMetadata(merged)
    }

    /// Explicitly removes one document, including its retained revisions.
    /// Generic `save` intentionally rejects document disappearance; callers
    /// must use this method to make deletion auditable and deliberate.
    @discardableResult
    public func deleteDocument(id documentID: UUID) throws -> PromptLibraryEnvelope {
        var library = try load()
        guard let index = library.documents.firstIndex(where: { $0.id == documentID }) else {
            throw PromptLibraryError.documentNotFound(documentID)
        }
        library.documents.remove(at: index)
        let validated = try library.validatingNormalized()
        try makeBackup()
        try writeAtomically(validated, to: urls.primary, protectUnreadable: false)
        return validated
    }

    /// Decodes an import without changing the repository file.
    public func importData(_ data: Data) throws -> PromptLibraryEnvelope {
        do {
            return try decode(data, sourceURL: nil)
        } catch let error as PromptLibraryError {
            throw PromptLibraryError.importRejected(reason: error.localizedDescription)
        } catch {
            throw PromptLibraryError.importRejected(reason: error.localizedDescription)
        }
    }

    public func importFile(from url: URL) throws -> PromptLibraryEnvelope {
        do {
            return try importData(Data(contentsOf: url))
        } catch let error as PromptLibraryError {
            throw error
        } catch {
            throw PromptLibraryError.importRejected(reason: error.localizedDescription)
        }
    }

    @discardableResult
    public func importAndMerge(from url: URL) throws -> PromptLibraryEnvelope {
        let imported = try importFile(from: url)
        return try merge(imported)
    }

    public func exportData(_ library: PromptLibraryEnvelope) throws -> Data {
        let normalized = try library.validatingNormalized()
        do {
            return try encoder.encode(normalized)
        } catch {
            throw PromptLibraryError.writeFailed(urls.primary, reason: error.localizedDescription)
        }
    }

    /// Exports to an explicit destination. It does not modify the repository.
    public func export(_ library: PromptLibraryEnvelope, to url: URL) throws {
        guard url.isFileURL else { throw PromptLibraryError.invalidFileURL }
        let normalized = try library.validatingNormalized()
        try writeAtomically(normalized, to: url, protectUnreadable: true)
    }

    /// Restores the last known-good backup, preserving a corrupt primary beside
    /// it before recovery. Recovery is explicit and never happens silently.
    @discardableResult
    public func recoverFromBackup() throws -> PromptLibraryEnvelope {
        guard fileManager.fileExists(atPath: urls.backup.path) else {
            throw PromptLibraryError.backupUnavailable(urls.backup)
        }
        let data: Data
        do {
            data = try Data(contentsOf: urls.backup)
        } catch {
            throw PromptLibraryError.corruptStore(urls.backup, reason: error.localizedDescription)
        }
        let library = try decode(data, sourceURL: urls.backup)
        if fileManager.fileExists(atPath: urls.primary.path) {
            let quarantineURL = urls.primary
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(UUID().uuidString).json")
            do {
                try fileManager.copyItem(at: urls.primary, to: quarantineURL)
            } catch {
                throw PromptLibraryError.writeFailed(quarantineURL, reason: error.localizedDescription)
            }
        }
        try writeAtomically(library, to: urls.primary, protectUnreadable: false)
        return library
    }

    public func recover() throws -> PromptLibraryEnvelope {
        try recoverFromBackup()
    }

    private func decode(_ data: Data, sourceURL: URL?) throws -> PromptLibraryEnvelope {
        do {
            return try decodeModern(data, sourceURL: sourceURL)
        } catch let error as PromptLibraryError {
            // A modern validation/format error is not a legacy payload. Keep
            // its typed meaning rather than attempting a lossy migration.
            if case .unsupportedFormat = error {
                throw error
            }
            if case .validationFailed = error {
                throw error
            }
        } catch {
            // Fall through to the legacy array decoder below.
        }
        do {
            let legacy: [LegacyPromptEntry]
            do {
                legacy = try decoder.decode([LegacyPromptEntry].self, from: data)
            } catch {
                // PromptStore historically used JSONEncoder's default Date
                // strategy (numeric seconds since the reference date).
                legacy = try legacyDecoder.decode([LegacyPromptEntry].self, from: data)
            }
            return try PromptLibraryMigration.migrate(legacy)
        } catch let migrationError as PromptLibraryError {
            throw migrationError
        } catch {
            let location = sourceURL ?? urls.primary
            throw PromptLibraryError.corruptStore(location, reason: error.localizedDescription)
        }
    }

    private func decodeModern(_ data: Data, sourceURL: URL?) throws -> PromptLibraryEnvelope {
        do {
            let library = try decoder.decode(PromptLibraryEnvelope.self, from: data)
            if library.formatVersion != PromptLibraryEnvelope.currentFormatVersion {
                throw PromptLibraryError.unsupportedFormat(library.formatVersion)
            }
            return try library.validatingNormalized()
        } catch {
            throw error
        }
    }

    private func enforceAppendOnly(
        existing: PromptLibraryEnvelope,
        proposed: PromptLibraryEnvelope
    ) throws {
        for existingDocument in existing.documents {
            guard let proposedDocument = proposed.documents.first(where: { $0.id == existingDocument.id }) else {
                throw PromptLibraryError.appendOnlyViolation(
                    path: "documents.\(existingDocument.id.uuidString)",
                    reason: "Existing documents cannot be deleted."
                )
            }
            guard proposedDocument.revisions.count >= existingDocument.revisions.count else {
                throw PromptLibraryError.appendOnlyViolation(
                    path: "documents.\(existingDocument.id.uuidString).revisions",
                    reason: "Existing revisions cannot be deleted."
                )
            }
            for (index, oldRevision) in existingDocument.revisions.enumerated() {
                guard proposedDocument.revisions[index] == oldRevision else {
                    throw PromptLibraryError.appendOnlyViolation(
                        path: "documents.\(existingDocument.id.uuidString).revisions[\(index)]",
                        reason: "Existing revisions cannot be edited or reordered."
                    )
                }
            }
        }
    }

    private func saveMetadata(_ library: PromptLibraryEnvelope) throws -> PromptLibraryEnvelope {
        let normalized = try library.validatingNormalized()
        if fileManager.fileExists(atPath: urls.primary.path) {
            try makeBackup()
        }
        try writeAtomically(normalized, to: urls.primary, protectUnreadable: false)
        return normalized
    }

    private func makeBackup() throws {
        let temporaryBackup = urls.backup
            .deletingLastPathComponent()
            .appendingPathComponent(".\(urls.backup.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            defer { try? fileManager.removeItem(at: temporaryBackup) }
            try fileManager.copyItem(at: urls.primary, to: temporaryBackup)
            if fileManager.fileExists(atPath: urls.backup.path) {
                _ = try fileManager.replaceItemAt(urls.backup, withItemAt: temporaryBackup)
            } else {
                try fileManager.moveItem(at: temporaryBackup, to: urls.backup)
            }
        } catch {
            throw PromptLibraryError.backupFailed(urls.backup, reason: error.localizedDescription)
        }
    }

    private func writeAtomically(
        _ library: PromptLibraryEnvelope,
        to url: URL,
        protectUnreadable: Bool
    ) throws {
        guard url.isFileURL else { throw PromptLibraryError.invalidFileURL }
        if protectUnreadable, fileManager.fileExists(atPath: url.path) {
            do {
                let existing = try Data(contentsOf: url)
                _ = try decode(existing, sourceURL: url)
            } catch {
                throw PromptLibraryError.existingStoreUnreadable(url, reason: error.localizedDescription)
            }
        }
        let parent = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporaryURL = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            let data = try encoder.encode(library)
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch let error as PromptLibraryError {
            throw error
        } catch {
            throw PromptLibraryError.writeFailed(url, reason: error.localizedDescription)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeLegacyDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

private struct LegacyPromptEntry: Codable, Hashable, Sendable {
    let id: UUID
    let original: String
    let refined: String
    let createdAt: Date
}

private nonisolated enum PromptLibraryMigration {
    static func migrate(_ entries: [LegacyPromptEntry]) throws -> PromptLibraryEnvelope {
        var documents: [PromptDocument] = []
        for entry in entries {
            let source = entry.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let refined = entry.refined.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleSource = refined.isEmpty ? source : refined
            let title = titleSource.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let revision = PromptRevision(
                id: entry.id,
                revisionNumber: 1,
                name: "Imported legacy prompt",
                createdAt: entry.createdAt,
                sourceText: source,
                compiledText: refined.isEmpty ? nil : refined,
                changeSummary: "Migrated from legacy prompt history"
            )
            documents.append(PromptDocument(
                id: entry.id,
                title: title.isEmpty ? PromptDocument.untitledTitle : title,
                createdAt: entry.createdAt,
                updatedAt: entry.createdAt,
                revisions: [revision]
            ))
        }
        let library = PromptLibraryEnvelope(documents: documents)
        do {
            return try library.validatingNormalized()
        } catch {
            throw PromptLibraryError.importRejected(reason: error.localizedDescription)
        }
    }
}
