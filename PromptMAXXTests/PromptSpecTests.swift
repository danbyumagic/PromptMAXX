import XCTest
@testable import PromptMAXX

final class PromptSpecTests: XCTestCase {
    func testNormalizationTrimsLinesDropsBlanksAndDeduplicatesLists() {
        let id = UUID()
        let spec = PromptSpec(
            id: id,
            title: "  A title\n\n",
            objective: "  First line\r\n second line ",
            context: "\n context ",
            constraints: [" one ", "", "one", "two\r\nlines", "two\nlines"],
            assumptions: [" assumption ", "assumption"],
            missingQuestions: [" question ", "question"],
            outputContract: " JSON only ",
            acceptanceCriteria: [" pass ", "", "pass"]
        )

        let normalized = spec.normalized
        XCTAssertEqual(normalized.id, id)
        XCTAssertEqual(normalized.title, "A title")
        XCTAssertEqual(normalized.objective, "First line\nsecond line")
        XCTAssertEqual(normalized.context, "context")
        XCTAssertEqual(normalized.constraints, ["one", "two\nlines"])
        XCTAssertEqual(normalized.assumptions, ["assumption"])
        XCTAssertEqual(normalized.missingQuestions, ["question"])
        XCTAssertEqual(normalized.outputContract, "JSON only")
        XCTAssertEqual(normalized.acceptanceCriteria, ["pass"])
    }

    func testBlankTitleNormalizesToUntitledAndValidationRequiresObjectiveAndContract() {
        let spec = PromptSpec(title: " \n\t")
        XCTAssertEqual(spec.normalized.title, PromptSpec.untitledTitle)
        XCTAssertFalse(spec.isValid)
        XCTAssertEqual(Set(spec.validationIssues.map(\.field)), ["objective", "outputContract"])
    }

    func testValidationRejectsUnsupportedSchemaButAllowsMissingQuestions() {
        let spec = PromptSpec(schemaVersion: 99, objective: "Do work", missingQuestions: ["What input?"] , outputContract: "Plain text")
        XCTAssertFalse(spec.isValid)
        XCTAssertEqual(spec.validationIssues.map(\.field), ["schemaVersion"])
    }
}
