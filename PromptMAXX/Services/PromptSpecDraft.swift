//
//  PromptSpecDraft.swift
//  PromptMAXX
//

import Foundation

/// The model-facing shape of a PromptSpec. It intentionally has no UUID: the
/// service owns identity so a model cannot replace or collide with a saved
/// spec's identity.
nonisolated public struct PromptSpecDraft: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var title: String
    public var objective: String
    public var context: String
    public var constraints: [String]
    public var assumptions: [String]
    public var missingQuestions: [String]
    public var outputContract: String
    public var acceptanceCriteria: [String]

    public init(
        schemaVersion: Int = PromptSpec.currentSchemaVersion,
        title: String = "",
        objective: String = "",
        context: String = "",
        constraints: [String] = [],
        assumptions: [String] = [],
        missingQuestions: [String] = [],
        outputContract: String = "",
        acceptanceCriteria: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.objective = objective
        self.context = context
        self.constraints = constraints
        self.assumptions = assumptions
        self.missingQuestions = missingQuestions
        self.outputContract = outputContract
        self.acceptanceCriteria = acceptanceCriteria
    }

    /// Tolerates omitted optional model fields while keeping the wire shape
    /// strict enough for validation after conversion.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? PromptSpec.currentSchemaVersion
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        objective = try values.decodeIfPresent(String.self, forKey: .objective) ?? ""
        context = try values.decodeIfPresent(String.self, forKey: .context) ?? ""
        constraints = try values.decodeIfPresent([String].self, forKey: .constraints) ?? []
        assumptions = try values.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        missingQuestions = try values.decodeIfPresent([String].self, forKey: .missingQuestions) ?? []
        outputContract = try values.decodeIfPresent(String.self, forKey: .outputContract) ?? ""
        acceptanceCriteria = try values.decodeIfPresent([String].self, forKey: .acceptanceCriteria) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case title
        case objective
        case context
        case constraints
        case assumptions
        case missingQuestions
        case outputContract
        case acceptanceCriteria
    }

    public var normalized: PromptSpecDraft {
        let spec = PromptSpec(
            schemaVersion: schemaVersion,
            title: title,
            objective: objective,
            context: context,
            constraints: constraints,
            assumptions: assumptions,
            missingQuestions: missingQuestions,
            outputContract: outputContract,
            acceptanceCriteria: acceptanceCriteria
        ).normalized

        return PromptSpecDraft(
            schemaVersion: spec.schemaVersion,
            title: spec.title,
            objective: spec.objective,
            context: spec.context,
            constraints: spec.constraints,
            assumptions: spec.assumptions,
            missingQuestions: spec.missingQuestions,
            outputContract: spec.outputContract,
            acceptanceCriteria: spec.acceptanceCriteria
        )
    }

    /// Creates an app-owned PromptSpec identity from this model output.
    public func toPromptSpec(id: UUID = UUID()) -> PromptSpec {
        let value = normalized
        return PromptSpec(
            id: id,
            schemaVersion: value.schemaVersion,
            title: value.title,
            objective: value.objective,
            context: value.context,
            constraints: value.constraints,
            assumptions: value.assumptions,
            missingQuestions: value.missingQuestions,
            outputContract: value.outputContract,
            acceptanceCriteria: value.acceptanceCriteria
        )
    }
}

nonisolated public struct PromptSpecGenerationResult: Codable, Hashable, Sendable {
    public let spec: PromptSpec
    public let compiledPrompt: String
    public let rawResponse: String
    public let attemptCount: Int
    public let model: String
    public let profileID: String
    public let startedAt: Date
    public let finishedAt: Date
    public let metrics: RunMetrics

    public init(
        spec: PromptSpec,
        compiledPrompt: String,
        rawResponse: String,
        attemptCount: Int,
        model: String,
        profileID: String,
        startedAt: Date,
        finishedAt: Date,
        metrics: RunMetrics
    ) {
        self.spec = spec
        self.compiledPrompt = compiledPrompt
        self.rawResponse = rawResponse
        self.attemptCount = attemptCount
        self.model = model
        self.profileID = profileID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.metrics = metrics
    }

    public var totalDurationMilliseconds: Double {
        metrics.totalDurationMilliseconds ?? max(0, finishedAt.timeIntervalSince(startedAt) * 1_000)
    }
}
