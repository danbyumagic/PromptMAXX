import Foundation

/// The presentation-ready line changes between an original and refined prompt.
///
/// Prompt changes are intentionally calculated locally. The inspector is a
/// factual view of text differences and does not make a quality judgment.
nonisolated public struct PromptDiff: Hashable, Sendable {
    nonisolated public enum LineKind: String, Hashable, Sendable {
        case unchanged
        case added
        case removed
    }

    nonisolated public struct Line: Hashable, Identifiable, Sendable {
        public let id: String
        public let kind: LineKind
        public let text: String
        public let originalLineNumber: Int?
        public let refinedLineNumber: Int?

        public init(
            id: String,
            kind: LineKind,
            text: String,
            originalLineNumber: Int?,
            refinedLineNumber: Int?
        ) {
            self.id = id
            self.kind = kind
            self.text = text
            self.originalLineNumber = originalLineNumber
            self.refinedLineNumber = refinedLineNumber
        }
    }

    public let lines: [Line]
    public let addedLineCount: Int
    public let removedLineCount: Int
    public let unchangedLineCount: Int

    public var hasChanges: Bool {
        addedLineCount > 0 || removedLineCount > 0
    }

    public var changedLineCount: Int {
        addedLineCount + removedLineCount
    }

    public init(original: String, refined: String) {
        let originalLines = Self.lines(in: original)
        let refinedLines = Self.lines(in: refined)
        let matrix = Self.longestCommonSubsequenceMatrix(originalLines, refinedLines)

        var result: [Line] = []
        result.reserveCapacity(originalLines.count + refinedLines.count)

        var originalIndex = 0
        var refinedIndex = 0
        var nextID = 0

        while originalIndex < originalLines.count || refinedIndex < refinedLines.count {
            if originalIndex < originalLines.count,
               refinedIndex < refinedLines.count,
               originalLines[originalIndex] == refinedLines[refinedIndex] {
                result.append(Line(
                    id: "unchanged-\(nextID)",
                    kind: .unchanged,
                    text: originalLines[originalIndex],
                    originalLineNumber: originalIndex + 1,
                    refinedLineNumber: refinedIndex + 1
                ))
                originalIndex += 1
                refinedIndex += 1
            } else if originalIndex < originalLines.count,
                      refinedIndex == refinedLines.count ||
                      matrix[originalIndex + 1][refinedIndex] >= matrix[originalIndex][refinedIndex + 1] {
                result.append(Line(
                    id: "removed-\(nextID)",
                    kind: .removed,
                    text: originalLines[originalIndex],
                    originalLineNumber: originalIndex + 1,
                    refinedLineNumber: nil
                ))
                originalIndex += 1
            } else {
                result.append(Line(
                    id: "added-\(nextID)",
                    kind: .added,
                    text: refinedLines[refinedIndex],
                    originalLineNumber: nil,
                    refinedLineNumber: refinedIndex + 1
                ))
                refinedIndex += 1
            }
            nextID += 1
        }

        lines = result
        addedLineCount = result.count(where: { $0.kind == .added })
        removedLineCount = result.count(where: { $0.kind == .removed })
        unchangedLineCount = result.count(where: { $0.kind == .unchanged })
    }

    private static func lines(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !normalized.isEmpty else { return [] }
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Builds a suffix LCS matrix. Prompt text is normally short, and keeping
    /// this calculation deterministic makes the displayed change order easy to
    /// reason about and test.
    private static func longestCommonSubsequenceMatrix(
        _ original: [String],
        _ refined: [String]
    ) -> [[Int]] {
        var matrix = Array(
            repeating: Array(repeating: 0, count: refined.count + 1),
            count: original.count + 1
        )

        for originalIndex in stride(from: original.count - 1, through: 0, by: -1) {
            for refinedIndex in stride(from: refined.count - 1, through: 0, by: -1) {
                if original[originalIndex] == refined[refinedIndex] {
                    matrix[originalIndex][refinedIndex] = matrix[originalIndex + 1][refinedIndex + 1] + 1
                } else {
                    matrix[originalIndex][refinedIndex] = max(
                        matrix[originalIndex + 1][refinedIndex],
                        matrix[originalIndex][refinedIndex + 1]
                    )
                }
            }
        }

        return matrix
    }
}
