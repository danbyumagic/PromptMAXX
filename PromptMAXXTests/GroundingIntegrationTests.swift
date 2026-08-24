import XCTest

@testable import PromptMAXX

final class GroundingIntegrationTests: XCTestCase {
  func testRuntimeTestFlagRequiresExplicitEnabledValue() {
    XCTAssertTrue(
      PromptMAXXRuntime.isRunningTests(environment: [
        PromptMAXXRuntime.testingEnvironmentKey: "1"
      ]))
    XCTAssertFalse(
      PromptMAXXRuntime.isRunningTests(environment: [
        PromptMAXXRuntime.testingEnvironmentKey: "0"
      ]))
    XCTAssertFalse(PromptMAXXRuntime.isRunningTests(environment: [:]))
  }

  func testHostedXCTestMarkersDisableAutomaticNetworking() {
    let hostedEnvironment: [String: String] = [
      "XCTestConfigurationFilePath": "/private/tmp/PromptMAXX.xctestconfiguration",
      "XCTestBundlePath": "/private/tmp/PromptMAXXTests.xctest",
      "XCInjectBundleInto": "/private/tmp/PromptMAXX.app"
    ]

    XCTAssertTrue(PromptMAXXRuntime.isRunningTests(environment: hostedEnvironment))
    XCTAssertFalse(PromptMAXXRuntime.automaticNetworkingAllowed(environment: hostedEnvironment))
    XCTAssertFalse(
      PromptMAXXRuntime.automaticNetworkingAllowed(environment: [
        PromptMAXXRuntime.testingEnvironmentKey: "1"
      ]))
    XCTAssertTrue(
      PromptMAXXRuntime.automaticNetworkingAllowed(environment: [
        PromptMAXXRuntime.testingEnvironmentKey: "0"
      ]))
    XCTAssertTrue(
      PromptMAXXRuntime.isRunningTests(
        environment: [:],
        arguments: ["PromptMAXX", PromptMAXXRuntime.testingArgument, "1"]))
    XCTAssertFalse(
      PromptMAXXRuntime.isRunningTests(
        environment: [:],
        arguments: ["PromptMAXX", PromptMAXXRuntime.testingArgument, "0"]))
  }

  func testCurrentHostedTestProcessDisablesAutomaticNetworking() {
    XCTAssertTrue(
      PromptMAXXRuntime.isRunningTests,
      "The test host must expose PROMPTMAXX_TESTING=1 or a standard XCTest host marker."
    )
    XCTAssertFalse(PromptMAXXRuntime.automaticNetworkingAllowed)
  }

  func testGroundingIndexLocationIsStableAndEndpointScoped() throws {
    let first = try OllamaEndpoint(host: "127.0.0.1", port: 11434)
    let same = try OllamaEndpoint(host: "127.0.0.1", port: 11434)
    let different = try OllamaEndpoint(host: "127.0.0.1", port: 11435)
    let fileManager = FileManager.default

    let firstURL = try GroundingIndexLocation.url(for: first, fileManager: fileManager)
    let sameURL = try GroundingIndexLocation.url(for: same, fileManager: fileManager)
    let differentURL = try GroundingIndexLocation.url(for: different, fileManager: fileManager)

    XCTAssertEqual(firstURL, sameURL)
    XCTAssertNotEqual(firstURL, differentURL)
    XCTAssertFalse(firstURL.lastPathComponent.contains("127.0.0.1"))
    XCTAssertTrue(firstURL.lastPathComponent.hasPrefix("grounding-"))
    XCTAssertTrue(firstURL.lastPathComponent.hasSuffix(".json"))
  }
}
