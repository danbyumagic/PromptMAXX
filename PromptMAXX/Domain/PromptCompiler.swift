//
//  PromptCompiler.swift
//  PromptMAXX
//

import Foundation

nonisolated public enum PromptCompilationError: Error, Codable, Hashable, Sendable, LocalizedError {
    case invalidSpec([PromptSpecValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .invalidSpec(let issues):
            return issues.map { "\($0.field): \($0.message)" }.joined(separator: " ")
        }
    }
}

/// Deterministically renders explicit PromptSpec fields into plain text.
/// There is no model call, implicit context, or hidden reasoning step here.
nonisolated public struct PromptCompiler: Sendable {
    public init() {}

    /// Compiles only a valid, normalized spec. Validation is performed before
    /// rendering so execution callers cannot accidentally run an incomplete
    /// contract.
    public func compile(_ spec: PromptSpec) throws -> String {
        let normalized = spec.normalized
        let issues = normalized.validationIssues
        guard issues.isEmpty else {
            throw PromptCompilationError.invalidSpec(issues)
        }
        return Self.render(normalized)
    }

    /// A convenience for call sites that prefer a type-directed API.
    public static func compile(_ spec: PromptSpec) throws -> String {
        try PromptCompiler().compile(spec)
    }

    /// Used by PromptSpec.compiledPrompt for previews and editor display. It
    /// intentionally remains total: invalid specs still produce a useful,
    /// deterministic preview while `compile(_:)` remains the validation gate.
    static func render(_ spec: PromptSpec) -> String {
        let normalized = spec.normalized
        var sections: [String] = []

        if !normalized.title.isEmpty {
            sections.append("Prompt: \(normalized.title)")
        }
        append("Objective", value: normalized.objective, to: &sections)
        append("Context", value: normalized.context, to: &sections)
        appendList("Constraints", values: normalized.constraints, to: &sections)
        appendList("Assumptions", values: normalized.assumptions, to: &sections)
        appendList("Open questions", values: normalized.missingQuestions, to: &sections)
        append("Output contract", value: normalized.outputContract, to: &sections)
        appendList("Acceptance criteria", values: normalized.acceptanceCriteria, to: &sections)

        return sections.joined(separator: "\n\n")
    }

    private static func append(_ heading: String, value: String, to sections: inout [String]) {
        guard !value.isEmpty else { return }
        sections.append("\(heading):\n\(value)")
    }

    private static func appendList(_ heading: String, values: [String], to sections: inout [String]) {
        guard !values.isEmpty else { return }
        let lines = values.map { "- \($0)" }.joined(separator: "\n")
        sections.append("\(heading):\n\(lines)")
    }
}
