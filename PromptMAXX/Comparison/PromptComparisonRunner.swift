import Foundation

/// Runs a bounded set of RefinementEngine executions. The default concurrency
/// is one because several local Ollama candidates can otherwise contend for RAM.
public actor PromptComparisonRunner {
    private let provider: any ModelProvider
    private let maxConcurrent: Int

    public init(provider: any ModelProvider, maxConcurrent: Int = 1) throws {
        guard (1...4).contains(maxConcurrent) else {
            throw PromptComparisonError.invalidConfiguration("Concurrency must be between one and four.")
        }
        self.provider = provider
        self.maxConcurrent = maxConcurrent
    }

    public func compare(_ configuration: PromptComparisonConfiguration) async -> PromptComparisonResult {
        let startedAt = Date()
        var results = Array(configuration.candidates.map {
            PromptCandidateResult(candidate: $0, status: .pending)
        })

        var offset = 0
        while offset < configuration.candidates.count {
            if Task.isCancelled {
                for index in offset..<configuration.candidates.count {
                    results[index] = Self.cancelledResult(for: configuration.candidates[index])
                }
                break
            }
            let end = min(offset + maxConcurrent, configuration.candidates.count)
            let batch = Array(configuration.candidates[offset..<end])
            let batchResults = await withTaskGroup(of: (Int, PromptCandidateResult).self, returning: [(Int, PromptCandidateResult)].self) { group in
                for (localIndex, candidate) in batch.enumerated() {
                    let absoluteIndex = offset + localIndex
                    group.addTask { [provider] in
                        let result = await Self.run(candidate: candidate, sourceText: configuration.sourceText, provider: provider)
                        return (absoluteIndex, result)
                    }
                }
                var values: [(Int, PromptCandidateResult)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (index, result) in batchResults { results[index] = result }
            offset = end
        }

        return PromptComparisonResult(
            sourceText: configuration.sourceText,
            candidates: results,
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    private static func run(
        candidate: PromptComparisonCandidate,
        sourceText: String,
        provider: any ModelProvider
    ) async -> PromptCandidateResult {
        let startedAt = Date()
        do {
            try Task.checkCancellation()
            let engine = RefinementEngine(provider: provider)
            let result = try await engine.generate(
                model: candidate.model,
                sourceText: sourceText,
                profile: candidate.profile
            )
            return PromptCandidateResult(
                candidate: candidate,
                status: .completed,
                attempts: result.attemptCount,
                spec: result.spec,
                compiledPrompt: result.compiledPrompt,
                metrics: result.metrics,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch is CancellationError {
            return PromptCandidateResult(
                candidate: candidate,
                status: .cancelled,
                attempts: 0,
                error: RunError(message: "Candidate generation was cancelled."),
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch let error as PromptSpecGenerationError {
            let validationFailure: String?
            switch error {
            case .invalidSpec(let issues):
                validationFailure = issues.map { "\($0.field): \($0.message)" }.joined(separator: " ")
            case .malformedJSON(let message), .compilation(let message):
                validationFailure = message
            default:
                validationFailure = nil
            }
            return PromptCandidateResult(
                candidate: candidate,
                status: .failed,
                attempts: 0,
                validationFailure: validationFailure,
                error: RunError(message: error.localizedDescription),
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            return PromptCandidateResult(
                candidate: candidate,
                status: .failed,
                attempts: 0,
                error: RunError(message: error.localizedDescription),
                startedAt: startedAt,
                finishedAt: Date()
            )
        }
    }

    private static func cancelledResult(for candidate: PromptComparisonCandidate) -> PromptCandidateResult {
        PromptCandidateResult(
            candidate: candidate,
            status: .cancelled,
            attempts: 0,
            error: RunError(message: "Candidate generation was cancelled before it started."),
            startedAt: nil,
            finishedAt: nil
        )
    }
}
