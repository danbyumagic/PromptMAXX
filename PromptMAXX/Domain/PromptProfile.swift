//
//  PromptProfile.swift
//  PromptMAXX
//

import Foundation

nonisolated public struct PromptGenerationOptions: Codable, Hashable, Sendable {
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var seed: Int?
    public var stream: Bool

    public init(
        temperature: Double = 0.2,
        topP: Double = 0.9,
        maxTokens: Int = 1024,
        seed: Int? = nil,
        stream: Bool = true
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.seed = seed
        self.stream = stream
    }

    /// Clamps provider-facing values while preserving optional seed/stream
    /// choices. This keeps malformed persisted settings from reaching a model.
    public var normalized: PromptGenerationOptions {
        PromptGenerationOptions(
            temperature: Self.finite(temperature, fallback: 0.2).clamped(to: 0...2),
            topP: Self.finite(topP, fallback: 0.9).clamped(to: 0...1),
            maxTokens: max(1, maxTokens),
            seed: seed,
            stream: stream
        )
    }

    public var isValid: Bool {
        temperature.isFinite && (0...2).contains(temperature) &&
        topP.isFinite && (0...1).contains(topP) &&
        maxTokens > 0
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }
}

nonisolated public struct PromptProfileValidationIssue: Codable, Hashable, Sendable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

/// A versioned instruction and generation policy for compiling/running specs.
/// Built-ins are immutable value constants; custom profiles can be decoded or
/// created by the UI without introducing persistence or networking coupling.
nonisolated public struct PromptProfile: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var version: Int
    public var name: String
    public var description: String
    public var systemPrompt: String
    public var generationOptions: PromptGenerationOptions

    public init(
        id: String,
        version: Int = 1,
        name: String,
        description: String,
        systemPrompt: String,
        generationOptions: PromptGenerationOptions = .init()
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.generationOptions = generationOptions
    }

    public static let concise = PromptProfile(
        id: "concise",
        name: "Concise",
        description: "A short, direct prompt with minimal ceremony.",
        systemPrompt: """
        Favor concise, direct instructions. Preserve the objective and explicit constraints. Avoid explanations, hidden reasoning, and unsupported requirements.
        """,
        generationOptions: .init(temperature: 0.2, topP: 0.9, maxTokens: 768)
    )

    public static let structured = PromptProfile(
        id: "structured",
        name: "Structured",
        description: "A clear prompt organized around objective, context, constraints, and acceptance criteria.",
        systemPrompt: """
        Favor clear, structured instructions. Preserve every explicit requirement, make assumptions visible, and use a predictable sectioned format when useful. Do not expose hidden reasoning or invent requirements.
        """,
        generationOptions: .init(temperature: 0.3, topP: 0.9, maxTokens: 1024)
    )

    public static let preserveVoice = PromptProfile(
        id: "preserve-voice",
        name: "Preserve Voice",
        description: "Improves clarity while retaining the author’s tone and distinctive wording.",
        systemPrompt: """
        Favor clarity and effectiveness while preserving the author's voice, tone, and meaningful wording. Make only necessary changes. Avoid explanations, hidden reasoning, and unsupported requirements.
        """,
        generationOptions: .init(temperature: 0.45, topP: 0.92, maxTokens: 1024)
    )

    public static let builtIns: [PromptProfile] = [
        .concise,
        .structured,
        .preserveVoice
    ]

    /// Creates a profile for the existing editable system-prompt setting.
    /// The generation service supplies the JSON contract around this policy.
    public static func custom(systemPrompt: String) -> PromptProfile {
        PromptProfile(
            id: "custom",
            version: 1,
            name: "Custom",
            description: "Uses the system prompt configured by the user.",
            systemPrompt: systemPrompt
        )
    }

    public var normalized: PromptProfile {
        PromptProfile(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            version: version,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            generationOptions: generationOptions.normalized
        )
    }

    public var validationIssues: [PromptProfileValidationIssue] {
        let profile = normalized
        var issues: [PromptProfileValidationIssue] = []
        if profile.id.isEmpty {
            issues.append(.init(field: "id", message: "A profile identity is required."))
        }
        if profile.version < 1 {
            issues.append(.init(field: "version", message: "Profile version must be positive."))
        }
        if profile.name.isEmpty {
            issues.append(.init(field: "name", message: "A profile name is required."))
        }
        if profile.description.isEmpty {
            issues.append(.init(field: "description", message: "A profile description is required."))
        }
        if profile.systemPrompt.isEmpty {
            issues.append(.init(field: "systemPrompt", message: "A system prompt is required."))
        }
        if !generationOptions.isValid {
            issues.append(.init(field: "generationOptions", message: "Generation options contain unsupported values."))
        }
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }
}

nonisolated private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
