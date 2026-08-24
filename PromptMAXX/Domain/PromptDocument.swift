//
//  PromptDocument.swift
//  PromptMAXX
//
//  Portable, persistence-ready prompt library values. These types deliberately
//  contain no UI or storage dependencies so they can be exported safely.
//

import Foundation

nonisolated public struct PromptLibraryValidationIssue: Codable, Hashable, Sendable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

nonisolated public struct PromptRevision: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public let revisionNumber: Int
    public var name: String
    public var createdAt: Date
    public var sourceText: String
    public var spec: PromptSpec?
    public var compiledText: String?
    public var changeSummary: String
    public var schemaVersion: Int
    public var profileID: String?
    public var profileVersion: Int?
    public var modelName: String?
    public var modelVersion: String?

    public init(
        id: UUID = UUID(),
        revisionNumber: Int,
        name: String = "",
        createdAt: Date = Date(),
        sourceText: String,
        spec: PromptSpec? = nil,
        compiledText: String? = nil,
        changeSummary: String = "",
        schemaVersion: Int = PromptRevision.currentSchemaVersion,
        profileID: String? = nil,
        profileVersion: Int? = nil,
        modelName: String? = nil,
        modelVersion: String? = nil
    ) {
        self.id = id
        self.revisionNumber = revisionNumber
        self.name = name
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.spec = spec
        self.compiledText = compiledText
        self.changeSummary = changeSummary
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.profileVersion = profileVersion
        self.modelName = modelName
        self.modelVersion = modelVersion
    }

    public var normalized: PromptRevision {
        PromptRevision(
            id: id,
            revisionNumber: revisionNumber,
            name: Self.normalizedText(name).isEmpty ? "Revision \(revisionNumber)" : Self.normalizedText(name),
            createdAt: createdAt,
            sourceText: Self.normalizedBlock(sourceText),
            spec: spec?.normalized,
            compiledText: Self.normalizedOptionalBlock(compiledText),
            changeSummary: Self.normalizedText(changeSummary),
            schemaVersion: schemaVersion,
            profileID: Self.normalizedOptionalText(profileID),
            profileVersion: profileVersion,
            modelName: Self.normalizedOptionalText(modelName),
            modelVersion: Self.normalizedOptionalText(modelVersion)
        )
    }

    public var validationIssues: [PromptLibraryValidationIssue] {
        let revision = normalized
        var issues: [PromptLibraryValidationIssue] = []
        if revision.revisionNumber < 1 {
            issues.append(.init(path: "revisionNumber", message: "Revision number must be positive."))
        }
        if revision.schemaVersion != Self.currentSchemaVersion {
            issues.append(.init(path: "schemaVersion", message: "Unsupported revision schema version \(revision.schemaVersion)."))
        }
        if revision.sourceText.isEmpty && (revision.compiledText ?? "").isEmpty && revision.spec == nil {
            issues.append(.init(path: "sourceText", message: "A revision must retain source text, compiled text, or a structured spec."))
        }
        if let profileVersion, profileVersion < 1 {
            issues.append(.init(path: "profileVersion", message: "Profile version must be positive."))
        }
        if profileVersion != nil && revision.profileID == nil {
            issues.append(.init(path: "profileID", message: "A profile ID is required when a profile version is recorded."))
        }
        if revision.modelVersion != nil && revision.modelName == nil {
            issues.append(.init(path: "modelName", message: "A model name is required when a model version is recorded."))
        }
        if let spec {
            issues += spec.validationIssues.map {
                .init(path: "spec.\($0.field)", message: $0.message)
            }
        }
        return issues
    }

    private static func normalizedText(_ value: String) -> String {
        normalizedLineEndings(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedBlock(_ value: String) -> String {
        normalizedLineEndings(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = normalizedText(value)
        return result.isEmpty ? nil : result
    }

    private static func normalizedOptionalBlock(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = normalizedBlock(value)
        return result.isEmpty ? nil : result
    }
}

nonisolated public struct PromptDocument: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1
    public static let untitledTitle = "Untitled Prompt"

    public let id: UUID
    public var title: String
    public var tags: [String]
    public var isFavorite: Bool
    public let createdAt: Date
    public var updatedAt: Date
    /// Revisions are append-only in repository APIs. Their array order is the
    /// canonical history order and is never reordered by normalization.
    public var revisions: [PromptRevision]

    public init(
        id: UUID = UUID(),
        title: String = PromptDocument.untitledTitle,
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revisions: [PromptRevision] = []
    ) {
        self.id = id
        self.title = title
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revisions = revisions
    }

    public var favorite: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }

    public var latestRevision: PromptRevision? { revisions.last }

    public var revisionCount: Int { revisions.count }

    public var displayText: String {
        let revision = latestRevision
        let compiled = revision?.compiledText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return compiled.isEmpty ? (revision?.sourceText ?? "") : compiled
    }

    public var wordCount: Int {
        displayText.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    public var normalized: PromptDocument {
        PromptDocument(
            id: id,
            title: Self.normalizedText(title).isEmpty ? Self.untitledTitle : Self.normalizedText(title),
            tags: Self.normalizedTags(tags),
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revisions: revisions.map(\.normalized)
        )
    }

    public var validationIssues: [PromptLibraryValidationIssue] {
        let document = normalized
        var issues: [PromptLibraryValidationIssue] = []
        if document.title.isEmpty {
            issues.append(.init(path: "title", message: "A document title is required."))
        }
        if document.updatedAt < document.createdAt {
            issues.append(.init(path: "updatedAt", message: "Updated time cannot precede creation time."))
        }
        if document.revisions.isEmpty {
            issues.append(.init(path: "revisions", message: "A document must contain at least one revision."))
        }

        var revisionIDs = Set<UUID>()
        var expectedNumber = 1
        var previousRevisionDate: Date?
        for (index, revision) in document.revisions.enumerated() {
            let path = "revisions[\(index)]"
            if !revisionIDs.insert(revision.id).inserted {
                issues.append(.init(path: "\(path).id", message: "Revision IDs must be unique."))
            }
            if revision.revisionNumber != expectedNumber {
                issues.append(.init(path: "\(path).revisionNumber", message: "Revision numbers must be contiguous and append-ordered."))
            }
            expectedNumber += 1
            if revision.createdAt < document.createdAt || revision.createdAt > document.updatedAt {
                issues.append(.init(
                    path: "\(path).createdAt",
                    message: "Revision time must fall within the document's created and updated times."
                ))
            }
            if let previousRevisionDate, revision.createdAt < previousRevisionDate {
                issues.append(.init(
                    path: "\(path).createdAt",
                    message: "Revision times must be nondecreasing."
                ))
            }
            previousRevisionDate = revision.createdAt
            issues += revision.validationIssues.map {
                .init(path: "\(path).\($0.path)", message: $0.message)
            }
        }
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }

    public func appending(_ revision: PromptRevision) throws -> PromptDocument {
        let normalizedDocument = normalized
        let nextNumber = (normalizedDocument.revisions.last?.revisionNumber ?? 0) + 1
        guard revision.revisionNumber == nextNumber else {
            throw PromptDocumentError.invalidRevisionNumber(expected: nextNumber, actual: revision.revisionNumber)
        }
        var result = normalizedDocument
        result.revisions.append(revision.normalized)
        result.updatedAt = max(result.updatedAt, revision.createdAt)
        return result
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map(normalizedText)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}

nonisolated public enum PromptDocumentError: Error, LocalizedError, Hashable, Sendable {
    case invalidRevisionNumber(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidRevisionNumber(expected, actual):
            return "Expected revision \(expected), received \(actual)."
        }
    }
}

nonisolated public struct PromptLibraryEnvelope: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var documents: [PromptDocument]

    public init(
        formatVersion: Int = PromptLibraryEnvelope.currentFormatVersion,
        documents: [PromptDocument] = []
    ) {
        self.formatVersion = formatVersion
        self.documents = documents
    }

    public var normalized: PromptLibraryEnvelope {
        PromptLibraryEnvelope(
            formatVersion: formatVersion,
            documents: documents.map(\.normalized)
        )
    }

    public var validationIssues: [PromptLibraryValidationIssue] {
        let library = normalized
        var issues: [PromptLibraryValidationIssue] = []
        if library.formatVersion != Self.currentFormatVersion {
            issues.append(.init(path: "formatVersion", message: "Unsupported library format version \(library.formatVersion)."))
        }
        var documentIDs = Set<UUID>()
        for (index, document) in library.documents.enumerated() {
            let path = "documents[\(index)]"
            if !documentIDs.insert(document.id).inserted {
                issues.append(.init(path: "\(path).id", message: "Document IDs must be unique."))
            }
            issues += document.validationIssues.map {
                .init(path: "\(path).\($0.path)", message: $0.message)
            }
        }
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }

    public func validatingNormalized() throws -> PromptLibraryEnvelope {
        let result = normalized
        let issues = result.validationIssues
        guard issues.isEmpty else {
            throw PromptLibraryError.validationFailed(issues)
        }
        return result
    }
}

/// Short alias for callers that prefer the library value rather than its wire
/// representation name.
public typealias PromptLibrary = PromptLibraryEnvelope
