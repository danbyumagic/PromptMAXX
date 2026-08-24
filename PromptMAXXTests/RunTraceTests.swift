import XCTest

@testable import PromptMAXX

final class RunTraceTests: XCTestCase {
    func testValidationCoversLifecycleAndMetrics() {
        XCTAssertTrue(RunTraceTestFixture.trace().isConsistent)

        let incomplete = RunTraceTestFixture.trace(
            run: RunRecord(
                model: "m", profileID: "p", profileVersion: 1, schemaVersion: 1,
                endpointLocality: .local, startedAt: RunTraceTestFixture.start,
                status: .completed),
            events: [])
        XCTAssertFalse(incomplete.isConsistent)

        let runningWithFinish = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(status: .running, finishedAt: RunTraceTestFixture.start),
            events: [])
        XCTAssertFalse(runningWithFinish.isConsistent)

        let failedWithoutExpectedPayload = RunTraceTestFixture.trace(
            run: RunRecord(
                model: "m", profileID: "p", profileVersion: 1, schemaVersion: 1,
                endpointLocality: .local, startedAt: RunTraceTestFixture.start,
                finishedAt: RunTraceTestFixture.start.addingTimeInterval(1), status: .failed),
            events: [RunTraceTestFixture.event()])
        XCTAssertFalse(failedWithoutExpectedPayload.isConsistent)

        let invalidMetrics = RunTraceTestFixture.trace(
            run: RunTraceTestFixture.run(metrics: RunMetrics(ttftMilliseconds: .nan)),
            events: [RunTraceTestFixture.event()])
        XCTAssertFalse(invalidMetrics.isConsistent)
    }
}
