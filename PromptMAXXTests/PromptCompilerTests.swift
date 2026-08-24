import XCTest
@testable import PromptMAXX

final class PromptCompilerTests: XCTestCase {
    func testCompilesValidSpecWithStableSectionsAndBullets() throws {
        let spec = PromptSpec(
            title: "Release note",
            objective: "Summarize the change",
            context: "The audience is technical",
            constraints: ["Use Markdown", "Stay under 100 words"],
            assumptions: ["The change is already merged"],
            missingQuestions: ["Which version?"] ,
            outputContract: "Return one paragraph",
            acceptanceCriteria: ["No unsupported claims"]
        )
        let compiled = try PromptCompiler().compile(spec)
        XCTAssertEqual(compiled, """
        Prompt: Release note

        Objective:
        Summarize the change

        Context:
        The audience is technical

        Constraints:
        - Use Markdown
        - Stay under 100 words

        Assumptions:
        - The change is already merged

        Open questions:
        - Which version?

        Output contract:
        Return one paragraph

        Acceptance criteria:
        - No unsupported claims
        """)
    }

    func testCompileRejectsInvalidSpecWithValidationIssues() {
        let spec = PromptSpec(title: "Missing fields")
        XCTAssertThrowsError(try PromptCompiler.compile(spec)) { error in
            guard case let PromptCompilationError.invalidSpec(issues) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(Set(issues.map(\.field)), ["objective", "outputContract"])
        }
    }

    func testPreviewRenderingRemainsUsefulForInvalidSpec() {
        let spec = PromptSpec(title: "Preview", objective: "Draft something")
        XCTAssertEqual(spec.compiledPrompt, "Prompt: Preview\n\nObjective:\nDraft something")
    }
}
