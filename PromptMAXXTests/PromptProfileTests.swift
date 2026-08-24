import XCTest
@testable import PromptMAXX

final class PromptProfileTests: XCTestCase {
    func testBuiltInProfilesAreValidVersionedAndDistinct() {
        XCTAssertEqual(PromptProfile.builtIns.count, 3)
        XCTAssertEqual(Set(PromptProfile.builtIns.map(\.id)).count, 3)
        for profile in PromptProfile.builtIns {
            XCTAssertTrue(profile.isValid, profile.id)
            XCTAssertGreaterThanOrEqual(profile.version, 1)
            XCTAssertFalse(profile.systemPrompt.isEmpty)
            XCTAssertTrue(profile.generationOptions.isValid)
        }
    }

    func testProfileNormalizationTrimsIdentityTextAndClampsOptions() {
        let profile = PromptProfile(
            id: " custom ", version: 2, name: " Name ", description: " Description ", systemPrompt: " System ",
            generationOptions: .init(temperature: 9, topP: -1, maxTokens: 0, seed: 42, stream: false)
        )
        let normalized = profile.normalized
        XCTAssertEqual(normalized.id, "custom")
        XCTAssertEqual(normalized.name, "Name")
        XCTAssertEqual(normalized.description, "Description")
        XCTAssertEqual(normalized.systemPrompt, "System")
        XCTAssertEqual(normalized.generationOptions.temperature, 2)
        XCTAssertEqual(normalized.generationOptions.topP, 0)
        XCTAssertEqual(normalized.generationOptions.maxTokens, 1)
        XCTAssertEqual(normalized.generationOptions.seed, 42)
        XCTAssertFalse(normalized.generationOptions.stream)
        XCTAssertTrue(normalized.isValid)
    }

    func testInvalidProfileReportsIdentityVersionAndRequiredFields() {
        let profile = PromptProfile(id: " ", version: 0, name: " ", description: " ", systemPrompt: " ")
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(Set(profile.validationIssues.map(\.field)), ["id", "version", "name", "description", "systemPrompt"])
    }

    func testInvalidGenerationOptionsAreReportedBeforeNormalization() {
        let options = PromptGenerationOptions(temperature: .nan, topP: .infinity, maxTokens: -1)
        XCTAssertFalse(options.isValid)
        let profile = PromptProfile(id: "p", name: "P", description: "D", systemPrompt: "S", generationOptions: options)
        XCTAssertFalse(profile.isValid, "raw invalid options should be reported")
        XCTAssertEqual(profile.normalized.generationOptions.temperature, 0.2)
        XCTAssertEqual(profile.normalized.generationOptions.topP, 0.9)
    }
}
