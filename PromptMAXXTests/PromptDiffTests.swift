import XCTest
@testable import PromptMAXX

final class PromptDiffTests: XCTestCase {
    func testIdenticalTextReportsOnlyUnchangedLines() {
        let diff = PromptDiff(original: "First line\nSecond line", refined: "First line\nSecond line")

        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(diff.addedLineCount, 0)
        XCTAssertEqual(diff.removedLineCount, 0)
        XCTAssertEqual(diff.unchangedLineCount, 2)
        XCTAssertEqual(diff.lines.map(\.kind), [.unchanged, .unchanged])
    }

    func testReplacementEmitsRemovedLineBeforeAddedLine() {
        let diff = PromptDiff(original: "Keep this\nBe vague", refined: "Keep this\nBe specific")

        XCTAssertEqual(diff.lines.map(\.kind), [.unchanged, .removed, .added])
        XCTAssertEqual(diff.lines[1].text, "Be vague")
        XCTAssertEqual(diff.lines[2].text, "Be specific")
        XCTAssertEqual(diff.lines[1].originalLineNumber, 2)
        XCTAssertEqual(diff.lines[2].refinedLineNumber, 2)
        XCTAssertEqual(diff.changedLineCount, 2)
    }

    func testInsertionAndDeletionKeepLineNumbersForBothSides() {
        let diff = PromptDiff(
            original: "Title\nBody\nSign off",
            refined: "Title\nContext\nBody"
        )

        XCTAssertEqual(diff.lines.map(\.kind), [.unchanged, .added, .unchanged, .removed])
        XCTAssertEqual(diff.lines[1].refinedLineNumber, 2)
        XCTAssertNil(diff.lines[1].originalLineNumber)
        XCTAssertEqual(diff.lines[2].originalLineNumber, 2)
        XCTAssertEqual(diff.lines[2].refinedLineNumber, 3)
        XCTAssertEqual(diff.lines[3].originalLineNumber, 3)
        XCTAssertNil(diff.lines[3].refinedLineNumber)
    }

    func testLineEndingDifferencesAreNotReportedAsPromptChanges() {
        let diff = PromptDiff(original: "One\r\nTwo\r\n", refined: "One\nTwo\n")

        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(diff.lines.count, 3)
        XCTAssertEqual(diff.unchangedLineCount, 3)
    }

    func testEmptyTextProducesAnEmptyDiff() {
        let diff = PromptDiff(original: "", refined: "")

        XCTAssertFalse(diff.hasChanges)
        XCTAssertTrue(diff.lines.isEmpty)
        XCTAssertEqual(diff.unchangedLineCount, 0)
    }
}
