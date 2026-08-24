import Foundation

/// A model/profile pairing to evaluate against one source prompt.
nonisolated public struct PromptComparisonCandidate: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let model: String
    public let profile: PromptProfile

    public init(id: String, model: String, profile: PromptProfile) throws {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw PromptComparisonError.invalidConfiguration("Each candidate needs an id.")
        }
        guard !normalizedModel.isEmpty else {
            throw PromptComparisonError.invalidConfiguration("Each candidate needs a model.")
        }
        guard profile.validationIssues.isEmpty else {
            throw PromptComparisonError.invalidConfiguration("Profile \(profile.name) is invalid.")
        }
        self.id = normalizedID
        self.model = normalizedModel
        self.profile = profile.normalized
    }

    public var label: String {
        "\(model) · \(profile.name)"
    }
}

/// Immutable input and execution policy for one comparison.
nonisolated public struct PromptComparisonConfiguration: Codable, Hashable, Sendable {
    public let sourceText: String
    public let candidates: [PromptComparisonCandidate]

    public init(sourceText: String, candidates: [PromptComparisonCandidate]) throws {
        let normalizedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else {
            throw PromptComparisonError.invalidConfiguration("Source text is required.")
        }
        guard (2...4).contains(candidates.count) else {
            throw PromptComparisonError.invalidConfiguration("Choose between two and four candidates.")
        }
        let IDs = candidates.map(\.id)
        guard Set(IDs).count == IDs.count else {
            throw PromptComparisonError.invalidConfiguration("Candidate ids must be unique.")
        }
        self.sourceText = normalizedSource
        self.candidates = candidates
    }
}

public enum PromptCandidateRunStatus: String, Codable, Hashable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

/// Facts captured for one candidate. There is deliberately no quality score:
/// comparison consumers should present the outputs and measurements for human review.
nonisolated public struct PromptCandidateResult: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let candidate: PromptComparisonCandidate
    public let status: PromptCandidateRunStatus
    /// The engine reports attempts on success. A failed/cancelled run reports
    /// zero because RefinementEngine does not expose a retry count on errors.
    public let attempts: Int
    public let spec: PromptSpec?
    public let compiledPrompt: String?
    public let validationFailure: String?
    public let error: RunError?
    public let metrics: RunMetrics
    public let startedAt: Date?
    public let finishedAt: Date?

    public init(
        candidate: PromptComparisonCandidate,
        status: PromptCandidateRunStatus,
        attempts: Int = 0,
        spec: PromptSpec? = nil,
        compiledPrompt: String? = nil,
        validationFailure: String? = nil,
        error: RunError? = nil,
        metrics: RunMetrics = .init(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = candidate.id
        self.candidate = candidate
        self.status = status
        self.attempts = attempts
        self.spec = spec
        self.compiledPrompt = compiledPrompt
        self.validationFailure = validationFailure
        self.error = error
        self.metrics = metrics
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var isSuccessful: Bool { status == .completed && compiledPrompt != nil }
}

nonisolated public struct PromptComparisonResult: Codable, Hashable, Sendable {
    public let sourceText: String
    public let candidates: [PromptCandidateResult]
    public let startedAt: Date
    public let finishedAt: Date

    public init(sourceText: String, candidates: [PromptCandidateResult], startedAt: Date, finishedAt: Date) {
        self.sourceText = sourceText
        self.candidates = candidates
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var completedCount: Int { candidates.filter { $0.status == .completed }.count }
    public var failedCount: Int { candidates.filter { $0.status == .failed }.count }
    public var cancelledCount: Int { candidates.filter { $0.status == .cancelled }.count }
}

nonisolated public enum PromptComparisonError: Error, LocalizedError, Codable, Hashable, Sendable {
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        }
    }
}
