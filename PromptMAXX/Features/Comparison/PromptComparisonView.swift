import SwiftUI

/// A factual side-by-side comparison view. It intentionally avoids ranking or
/// scoring candidates because quality judgments require user review.
public struct PromptComparisonView: View {
    public let result: PromptComparisonResult
    @Environment(\.dismiss) private var dismiss

    public init(result: PromptComparisonResult) {
        self.result = result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Candidate Comparison")
                        .font(.title2.bold())
                    Text("\(result.completedCount) completed · \(result.failedCount) failed · \(result.cancelledCount) cancelled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Source prompt") {
                        Text(result.sourceText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityLabel("Source prompt")
                    }

                    ForEach(result.candidates) { candidate in
                        candidateCard(candidate)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    @ViewBuilder
    private func candidateCard(_ candidate: PromptCandidateResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.candidate.label)
                            .font(.headline)
                        Text("Profile: \(candidate.candidate.profile.name) · Attempts: \(candidate.attempts)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(candidate.status.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(candidate.status))
                        .accessibilityLabel("Status: \(candidate.status.rawValue)")
                }

                if let output = candidate.compiledPrompt {
                    Text(output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityLabel("Compiled prompt for \(candidate.candidate.label)")
                } else if let validationFailure = candidate.validationFailure {
                    Label("Validation: \(validationFailure)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else if let error = candidate.error?.message {
                    Label(error, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack(spacing: 12) {
                    if let duration = candidate.metrics.totalDurationMilliseconds {
                        metric("Latency", value: String(format: "%.0f ms", duration))
                    }
                    if let ttft = candidate.metrics.ttftMilliseconds {
                        metric("TTFT", value: String(format: "%.0f ms", ttft))
                    }
                    if let input = candidate.metrics.inputTokenCount {
                        metric("Input", value: "\(input) tokens")
                    }
                    if let output = candidate.metrics.outputTokenCount {
                        metric("Output", value: "\(output) tokens")
                    }
                    Spacer()
                }
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func statusColor(_ status: PromptCandidateRunStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .pending, .running: return .secondary
        }
    }
}
