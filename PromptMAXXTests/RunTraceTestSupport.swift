import Foundation
@testable import PromptMAXX

enum RunTraceTestFixture {
    static let start = Date(timeIntervalSince1970: 1_000)

    static func run(
        status: RunStatus = .completed,
        startedAt: Date = start,
        finishedAt: Date? = nil,
        model: String = "phi4-mini",
        modelVersion: String? = "digest-a",
        profileID: String = "concise",
        profileVersion: Int = 1,
        schemaVersion: Int = 1,
        endpointLocality: EndpointLocality = .local,
        metrics: RunMetrics = RunMetrics(
            ttftMilliseconds: 10, totalDurationMilliseconds: 40,
            inputTokenCount: 5, outputTokenCount: 7),
        output: String? = "model output",
        error: RunError? = nil,
        cancellation: RunCancellation? = nil
    ) -> RunRecord {
        let terminalFinish = finishedAt ?? (status.isTerminal ? startedAt.addingTimeInterval(1) : nil)
        let effectiveError = status == .failed ? (error ?? RunError(domain: "test", code: 7, message: "provider failed")) : error
        let effectiveCancellation = status == .cancelled ? (cancellation ?? RunCancellation(reason: .userRequested, requestedAt: startedAt.addingTimeInterval(0.5))) : cancellation
        let effectiveOutput = status == .completed ? output : nil
        return RunRecord(
            model: model, modelVersion: modelVersion, profileID: profileID,
            profileVersion: profileVersion, schemaVersion: schemaVersion,
            endpointLocality: endpointLocality, startedAt: startedAt,
            finishedAt: terminalFinish, status: status, metrics: metrics,
            output: effectiveOutput, error: effectiveError,
            cancellation: effectiveCancellation)
    }

    static func event(
        stage: TraceStage = .prepare,
        startedAt: Date = start,
        finishedAt: Date? = start.addingTimeInterval(0.1),
        summary: String = "Prepared request"
    ) -> TraceStageEvent {
        TraceStageEvent(stage: stage, startedAt: startedAt, finishedAt: finishedAt, summary: summary)
    }

    static func trace(
        run: RunRecord? = nil,
        kind: TraceKind = .refinement,
        sourceText: String? = "source",
        renderedInput: String? = "rendered",
        compiledPrompt: String? = "compiled",
        provider: String = "ollama",
        endpointLabel: String = "loopback",
        generationOptions: PromptGenerationOptions = .init(),
        events: [TraceStageEvent]? = nil
    ) -> RunTrace {
        let effectiveRun = run ?? self.run()
        return RunTrace(
            run: effectiveRun, kind: kind, promptSpecID: UUID(), revisionID: UUID(),
            sourceText: sourceText, renderedInput: renderedInput,
            compiledPrompt: compiledPrompt, provider: provider,
            endpointLabel: endpointLabel, generationOptions: generationOptions,
            events: events ?? [self.event(startedAt: effectiveRun.startedAt,
                                           finishedAt: effectiveRun.startedAt.addingTimeInterval(0.1))])
    }
}
