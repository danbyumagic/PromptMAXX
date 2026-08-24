import XCTest
@testable import PromptMAXX

final class EvaluationLabFormattingTests: XCTestCase {
    func testSafeFilenameComponentRemovesPathAndPunctuation() {
        XCTAssertEqual(
            EvaluationLabFormatting.safeFilenameComponent(" support/ticket:json? "),
            "support-ticket-json"
        )
        XCTAssertEqual(EvaluationLabFormatting.safeFilenameComponent("---"), "evaluation")
    }

    func testFilenameUsesSafeSuiteIDAndExtension() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            EvaluationLabFormatting.filename(
                suiteID: "support/ticket",
                fileExtension: "Markdown",
                date: date
            ),
            "promptmaxx-evaluation-support-ticket-19700101-000000.markdown"
        )
    }

    func testMarkdownIncludesConfigurationAndRawEvidence() {
        let candidate = BuiltInBenchmark.originalCandidate(model: "test-model")
        let embeddedBackticks = "{\"note\":\"``` embedded\"}"
        let result = EvalCaseResult(
            caseID: "case-1",
            suiteCaseVersion: 1,
            candidateID: candidate.id,
            candidateLabel: candidate.label,
            candidateVersion: candidate.version,
            model: candidate.model,
            output: embeddedBackticks,
            error: nil,
            checkResults: [EvalCheckResult(checkID: "json", label: "Valid JSON", passed: true, detail: "Passed")],
            latencyMilliseconds: 12,
            inputTokenCount: 3,
            outputTokenCount: 4
        )
        let report = EvalReport(
            suite: EvalSuite(id: "suite", name: "Suite", cases: [EvalCase(id: "case-1", name: "Case", input: "input", checks: [EvalCheck(id: "json", kind: .validJSON)])]),
            candidates: [candidate],
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 1),
            results: [result]
        )

        let markdown = EvaluationLabFormatting.markdown(report: report)
        XCTAssertTrue(markdown.contains("temperature"))
        XCTAssertTrue(markdown.contains(embeddedBackticks.replacingOccurrences(of: "```", with: "``\u{200B}`")))
        XCTAssertFalse(markdown.contains("\\u{200B}"))
        XCTAssertTrue(markdown.contains("Started:"))
        XCTAssertTrue(markdown.contains("Finished:"))
        XCTAssertTrue(markdown.contains("Timing note:"))
        XCTAssertTrue(markdown.contains("mechanical checks only"))
    }

    func testBuiltInCandidatesShareDeterministicGenerationConfiguration() {
        let original = BuiltInBenchmark.originalCandidate(model: "test-model")
        let refined = BuiltInBenchmark.refinedCandidate(model: "test-model")

        XCTAssertEqual(original.generationOptions, refined.generationOptions)
        XCTAssertEqual(original.generationOptions.seed, 42)
        XCTAssertEqual(original.format, .json)
        XCTAssertEqual(refined.format, .json)
    }
}
