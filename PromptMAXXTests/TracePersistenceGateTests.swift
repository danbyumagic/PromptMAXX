import XCTest
@testable import PromptMAXX

final class TracePersistenceGateTests: XCTestCase {
  func testActiveRunMayPersist() {
    let token = UUID()
    XCTAssertTrue(TracePersistenceGate.permits(
      capturedToken: token, activeToken: token, isCancelled: false))
  }

  func testCancelledAndSupersededRunsCannotPersist() {
    let token = UUID()
    XCTAssertFalse(TracePersistenceGate.permits(
      capturedToken: token, activeToken: token, isCancelled: true))
    XCTAssertFalse(TracePersistenceGate.permits(
      capturedToken: token, activeToken: UUID(), isCancelled: false))
    XCTAssertFalse(TracePersistenceGate.permits(
      capturedToken: token, activeToken: nil, isCancelled: false))
  }
}
