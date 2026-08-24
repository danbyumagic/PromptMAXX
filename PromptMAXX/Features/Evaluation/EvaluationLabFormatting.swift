import Foundation

/// Presentation-only formatting used by the Evaluation Lab and its exports.
public enum EvaluationLabFormatting {
    public static func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let collapsed = mapped.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "evaluation" : trimmed
    }

    public static func filename(suiteID: String, fileExtension: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suite = safeFilenameComponent(suiteID)
        let ext = safeFilenameComponent(fileExtension).lowercased()
        return "promptmaxx-evaluation-\(suite)-\(formatter.string(from: date)).\(ext)"
    }

    public static func percentage(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    /// A complete, factual Markdown representation of an evaluation report.
    /// Unlike a ranking, it includes the raw evidence and mechanical checks.
    public static func markdown(report: EvalReport) -> String {
        var lines = [
            "# Evaluation: \(report.suite.name)",
            "",
            "- Suite ID: `\(report.suite.id)` (v\(report.suite.version))",
            "- Cases: \(report.suite.cases.count)",
            "- Interpretation: mechanical checks only; this report does not assess subjective quality or choose a winner.",
            "- Timing note: latency includes runtime and possible model warm-up; compare candidates with care.",
            "- Started: \(iso8601(report.startedAt))",
            "- Finished: \(iso8601(report.finishedAt))",
            "",
            report.suite.description,
            "",
            "## Candidate summaries",
            "",
            "| Candidate | Model | Pass rate | Passed | Avg latency | Avg input tokens | Avg output tokens |",
            "| --- | --- | ---: | ---: | ---: | ---: | ---: |"
        ]

        for summary in report.summaries {
            lines.append(
                "| \(escape(summary.candidateLabel)) | \(escape(summary.model)) | \(percentage(summary.passRate)) | \(summary.passedCases)/\(summary.totalCases) | \(metric(summary.averageLatencyMilliseconds, suffix: " ms")) | \(metric(summary.averageInputTokens)) | \(metric(summary.averageOutputTokens)) |"
            )
        }

        lines += ["", "## Candidate configuration", ""]
        for candidate in report.candidates {
            lines.append("### \(escape(candidate.label)) (`\(candidate.id)`)")
            lines.append("- Model: `\(escape(candidate.model))`")
            lines.append("- Format: \(candidate.format?.rawValue ?? "text")")
            lines.append("- Options: \(options(candidate.generationOptions))")
            lines.append("- Instruction: \(codeBlock(candidate.instruction))")
            lines.append("")
        }

        lines += ["## Case evidence", ""]
        for result in report.results {
            lines.append("### \(escape(result.candidateLabel)) — \(escape(result.caseID))")
            lines.append("- Result: **\(result.passed ? "PASS" : "FAIL")**")
            if let latency = result.latencyMilliseconds {
                lines.append("- Latency: \(String(format: "%.1f ms", latency))")
            }
            if let input = result.inputTokenCount { lines.append("- Input tokens: \(input)") }
            if let output = result.outputTokenCount { lines.append("- Output tokens: \(output)") }
            if let error = result.error {
                lines.append("- Error: \(escape(error))")
            }
            lines.append("- Checks: \(result.checksPassed)/\(result.checkResults.count)")
            for check in result.checkResults {
                lines.append("  - [\(check.passed ? "x" : " ")] \(escape(check.label)): \(escape(check.detail))")
            }
            if let output = result.output {
                lines += ["", "Output:", "", codeBlock(output), ""]
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func metric(_ value: Double?, suffix: String = "") -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value) + suffix
    }

    private static func options(_ value: PromptGenerationOptions) -> String {
        let seed = value.seed.map(String.init) ?? "—"
        return "temperature \(String(format: "%.2f", value.temperature)), top-p \(String(format: "%.2f", value.topP)), max tokens \(value.maxTokens), seed \(seed), streaming \(value.stream ? "yes" : "no")"
    }

    private static func codeBlock(_ value: String) -> String {
        "```\n\(value.replacingOccurrences(of: "```", with: "``\u{200B}`"))\n```"
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
