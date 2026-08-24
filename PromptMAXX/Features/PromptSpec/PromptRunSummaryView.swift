//
//  PromptRunSummaryView.swift
//  PromptMAXX
//

import SwiftUI

/// A compact factual summary of one generation run. It intentionally reports
/// observed metadata only; it does not manufacture a quality or confidence
/// score from latency or token counts.
public struct PromptRunSummaryView: View {
    private let result: PromptSpecGenerationResult
    private let profileDisplayName: String

    public init(result: PromptSpecGenerationResult, profileDisplayName: String) {
        self.result = result
        self.profileDisplayName = profileDisplayName
    }

    /// Compatibility spelling for existing callers that use the shorter UI
    /// label while retaining the same profile display-name semantics.
    public init(result: PromptSpecGenerationResult, profileName: String) {
        self.init(result: result, profileDisplayName: profileName)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(.purple)
                Text("Run Summary")
                    .font(.headline)
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                summaryRow("Profile", value: profileDisplayName)
                summaryRow("Model", value: result.model)
                summaryRow("Attempts", value: "\(result.attemptCount)")
                summaryRow("Time to first token", value: formatMilliseconds(result.metrics.ttftMilliseconds))
                summaryRow("Total latency", value: formatMilliseconds(result.metrics.totalDurationMilliseconds))
                summaryRow("Input tokens", value: formatCount(result.metrics.inputTokenCount))
                summaryRow("Output tokens", value: formatCount(result.metrics.outputTokenCount))
            }
            .font(.system(.callout, design: .rounded))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
        }
        .padding(16)
        .frame(minWidth: 270, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    private func formatMilliseconds(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value < 1 {
            return String(format: "%.2f ms", value)
        }
        if value < 100 {
            return String(format: "%.1f ms", value)
        }
        return String(format: "%.0f ms", value)
    }

    private func formatCount(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return value.formatted()
    }

    private var accessibilitySummary: String {
        "Run summary. Profile \(profileDisplayName). Model \(result.model). \(result.attemptCount) attempts. Time to first token \(formatMilliseconds(result.metrics.ttftMilliseconds)). Total latency \(formatMilliseconds(result.metrics.totalDurationMilliseconds)). Input tokens \(formatCount(result.metrics.inputTokenCount)). Output tokens \(formatCount(result.metrics.outputTokenCount))."
    }
}

#Preview {
    PromptRunSummaryView(
        result: PromptSpecGenerationResult(
            spec: PromptSpec(
                title: "Release notes",
                objective: "Summarize changes.",
                outputContract: "Markdown bullets"
            ),
            compiledPrompt: "Objective:\nSummarize changes.",
            rawResponse: "{}",
            attemptCount: 1,
            model: "phi4-mini:latest",
            profileID: "structured",
            startedAt: Date().addingTimeInterval(-1.23),
            finishedAt: Date(),
            metrics: RunMetrics(
                ttftMilliseconds: 180,
                totalDurationMilliseconds: 1_230,
                inputTokenCount: 72,
                outputTokenCount: 44
            )
        ),
        profileDisplayName: "Structured"
    )
}
