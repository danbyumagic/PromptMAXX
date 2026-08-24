import XCTest

@testable import PromptMAXX

final class GroundingInspectorFormattingTests: XCTestCase {
  func testRankingSignalsAndProvenanceAreExplicitAndDeterministic() {
    XCTAssertEqual(GroundingInspectorFormatting.score(0.125), "0.1250")
    XCTAssertEqual(
      GroundingInspectorFormatting.location(
        GroundingProvenance(sourceID: "source", sourceName: "Notes", ordinal: 3)),
      "Chunk ordinal 3")
    XCTAssertEqual(
      GroundingInspectorFormatting.location(
        GroundingProvenance(sourceID: "source", sourceName: "Notes", page: 2, ordinal: 3)),
      "Page 2 · chunk ordinal 3")
  }
}
