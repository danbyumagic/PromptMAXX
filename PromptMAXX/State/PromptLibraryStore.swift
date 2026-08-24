//
//  PromptLibraryStore.swift
//  PromptMAXX
//
//  Main-actor application state over the durable prompt library repository.
//

import Foundation
import Observation

public protocol PromptLibraryClock: Sendable {
    func now() -> Date
}

nonisolated public struct SystemPromptLibraryClock: PromptLibraryClock {
    nonisolated public init() {}
    nonisolated public func now() -> Date { Date() }
}

public enum PromptLibraryStoreState: Equatable, Sendable {
    case loading
    case ready
    case failed
}

@MainActor @Observable
public final class PromptLibraryStore {
    public static let legacyHistoryKey = "promptHistory"
    public static let migrationMarkerKey = "promptHistoryMigrationVersion"
    public static let currentMigrationVersion = 1

    public let repository: PromptLibraryRepository
    public let userDefaults: UserDefaults
    public let clock: any PromptLibraryClock
    public let migrationEnabled: Bool

    public private(set) var documents: [PromptDocument] = []
    public private(set) var state: PromptLibraryStoreState = .loading
    public private(set) var persistenceError: PromptLibraryError?
    public private(set) var isLoading = true
    public private(set) var isSaving = false

    private var didAttemptLoad = false

    public var history: [PromptDocument] {
        documents.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public var hasBackup: Bool {
        FileManager.default.fileExists(atPath: repository.urls.backup.path)
    }

    public init(
        repository: PromptLibraryRepository,
        userDefaults: UserDefaults,
        clock: any PromptLibraryClock = SystemPromptLibraryClock(),
        migrationEnabled: Bool = true
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        self.clock = clock
        self.migrationEnabled = migrationEnabled
    }

    public convenience init() {
        let fileURL = (try? PromptLibraryRepository.defaultFileURL())
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("PromptMAXX", isDirectory: true)
                .appendingPathComponent("prompt-library.json", isDirectory: false)
        self.init(
            repository: PromptLibraryRepository(fileURL: fileURL),
            userDefaults: .standard
        )
    }

    /// Loads once per shared app store. A failed load remains visible to the
    /// UI and can be retried explicitly; it never falls back over corruption.
    public func loadIfNeeded(force: Bool = false) async {
        guard force || !didAttemptLoad else { return }
        didAttemptLoad = true
        isLoading = true
        state = .loading
        persistenceError = nil

        do {
            do {
                let library = try await repository.load()
                documents = library.documents
                // A successful modern load supersedes any legacy defaults.
                // Record that fact even when the old bytes remain available
                // as a recovery source, so a later library deletion cannot
                // resurrect stale history.
                if migrationEnabled,
                   userDefaults.integer(forKey: Self.migrationMarkerKey) < Self.currentMigrationVersion {
                    userDefaults.set(Self.currentMigrationVersion, forKey: Self.migrationMarkerKey)
                }
            } catch let error as PromptLibraryError {
                guard case .fileNotFound = error else { throw error }
                if migrationEnabled,
                   userDefaults.integer(forKey: Self.migrationMarkerKey) < Self.currentMigrationVersion,
                   let legacyData = userDefaults.data(forKey: Self.legacyHistoryKey) {
                    let migrated = try await repository.importData(legacyData)
                    let saved = try await repository.save(migrated)
                    // The legacy bytes intentionally remain untouched as a
                    // recovery source. Mark only after atomic save succeeds.
                    userDefaults.set(Self.currentMigrationVersion, forKey: Self.migrationMarkerKey)
                    documents = saved.documents
                } else {
                    documents = []
                }
            }
            isLoading = false
            state = .ready
        } catch let error as PromptLibraryError {
            isLoading = false
            state = .failed
            persistenceError = error
        } catch {
            isLoading = false
            state = .failed
            persistenceError = .importRejected(reason: error.localizedDescription)
        }
    }

    @discardableResult
    public func saveEditor(
        documentID: UUID?,
        originalText: String,
        refinedText: String,
        spec: PromptSpec?,
        profile: PromptProfile?,
        modelName: String?,
        modelVersion: String? = nil,
        changeSummary: String = "Saved editor changes"
    ) async -> PromptDocument? {
        guard !isSaving else { return nil }
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }

        if let documentID,
           let document = documents.first(where: { $0.id == documentID }),
           let latest = document.latestRevision,
           latest.sourceText == Self.normalizedBlock(originalText),
           latest.compiledText == Self.normalizedOptionalBlock(refinedText),
           latest.spec == spec?.normalized {
            // A caller can arrive here after a view refresh even though no
            // editor field changed. Preserve append-only history by treating
            // an identical revision as an idempotent save.
            return document
        }
        let timestamp = clock.now()
        let initialRevisionNumber = documentID == nil ? 1 : 0
        let revision = PromptRevision(
            revisionNumber: initialRevisionNumber,
            name: initialRevisionNumber == 0 ? "" : "Revision 1",
            createdAt: timestamp,
            sourceText: originalText,
            spec: spec,
            compiledText: refinedText.isEmpty ? nil : refinedText,
            changeSummary: changeSummary,
            schemaVersion: PromptRevision.currentSchemaVersion,
            profileID: profile?.id,
            profileVersion: profile?.version,
            modelName: modelName,
            modelVersion: modelVersion
        )

        do {
            let library: PromptLibraryEnvelope
            if let documentID {
                // The repository assigns the next revision number from its
                // current library inside the actor transaction. This remains
                // correct when another window has appended since our local
                // snapshot was loaded.
                library = try await repository.appendRevisionAssigningNextNumber(revision, to: documentID)
            } else {
                let title = Self.title(for: refinedText.isEmpty ? originalText : refinedText, spec: spec)
                let document = PromptDocument(
                    title: title,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    revisions: [revision]
                )
                library = try await repository.createDocument(document)
            }
            documents = library.documents
            let savedID = documentID ?? library.documents.first(where: { $0.revisions.contains(where: { $0.id == revision.id }) })?.id
            return library.documents.first(where: { $0.id == savedID })
        } catch let error as PromptLibraryError {
            persistenceError = error
            return nil
        } catch {
            persistenceError = .writeFailed(repository.urls.primary, reason: error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    public func deleteDocument(id: UUID) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            let library = try await repository.deleteDocument(id: id)
            documents = library.documents
            return true
        } catch let error as PromptLibraryError {
            persistenceError = error
            return false
        } catch {
            persistenceError = .writeFailed(repository.urls.primary, reason: error.localizedDescription)
            return false
        }
    }

    public func clearPersistenceError() {
        persistenceError = nil
    }

    public func setFavorite(_ favorite: Bool, for documentID: UUID) async -> Bool {
        guard state == .ready, !isSaving else { return false }
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            let library = try await repository.setFavorite(favorite, for: documentID)
            documents = library.documents
            return true
        } catch let error as PromptLibraryError {
            persistenceError = error
            return false
        } catch {
            persistenceError = .writeFailed(repository.urls.primary, reason: error.localizedDescription)
            return false
        }
    }

    public func importLibrary(from url: URL) async -> Bool {
        guard state == .ready, !isSaving else { return false }
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            let library = try await repository.importAndMerge(from: url)
            documents = library.documents
            return true
        } catch let error as PromptLibraryError {
            persistenceError = error
            return false
        } catch {
            persistenceError = .importRejected(reason: error.localizedDescription)
            return false
        }
    }

    public func exportLibrary(to url: URL) async -> Bool {
        guard state == .ready, !isSaving else { return false }
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            try await repository.export(PromptLibraryEnvelope(documents: documents), to: url)
            return true
        } catch let error as PromptLibraryError {
            persistenceError = error
            return false
        } catch {
            persistenceError = .writeFailed(url, reason: error.localizedDescription)
            return false
        }
    }

    public func recoverBackup() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            let library = try await repository.recoverFromBackup()
            documents = library.documents
            state = .ready
            isLoading = false
            didAttemptLoad = true
            return true
        } catch let error as PromptLibraryError {
            persistenceError = error
            state = .failed
            return false
        } catch {
            persistenceError = .writeFailed(repository.urls.primary, reason: error.localizedDescription)
            state = .failed
            return false
        }
    }

    public func filteredHistory(search query: String) -> [PromptDocument] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return history }
        return history.filter { Self.matches($0, query: normalizedQuery) }
    }

    public static func matches(_ document: PromptDocument, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        let revision = document.latestRevision
        let haystacks = [
            document.title,
            document.tags.joined(separator: " "),
            revision?.sourceText ?? "",
            revision?.compiledText ?? ""
        ]
        return haystacks.contains { $0.lowercased().contains(needle) }
    }

    private static func title(for text: String, spec: PromptSpec?) -> String {
        if let specTitle = spec?.normalized.title,
           !specTitle.isEmpty,
           specTitle != PromptSpec.untitledTitle {
            return specTitle
        }
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !firstLine.isEmpty else { return PromptDocument.untitledTitle }
        return firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
    }

    private static func normalizedBlock(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedOptionalBlock(_ value: String) -> String? {
        let normalized = normalizedBlock(value)
        return normalized.isEmpty ? nil : normalized
    }
}
