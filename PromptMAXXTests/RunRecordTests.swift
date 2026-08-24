import XCTest
@testable import PromptMAXX

final class RunRecordTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testRunningRecordIsConsistentWithoutTerminalPayload() {
        let record = make(status: .running)
        XCTAssertTrue(record.isConsistent)
        XCTAssertFalse(record.status.isTerminal)
        XCTAssertNil(record.finishedAt)
    }

    func testCompletedRecordRequiresFinishAndHasOutput() {
        let record = make(finishedAt: start.addingTimeInterval(2), status: .completed, output: "done")
        XCTAssertTrue(record.isConsistent)
        XCTAssertTrue(record.status.isTerminal)
        XCTAssertEqual(record.output, "done")
        XCTAssertFalse(make(status: .completed).isConsistent)
    }

    func testFailedRecordRequiresErrorAndFinish() {
        let error = RunError(domain: "provider", code: 503, message: "Unavailable")
        XCTAssertTrue(make(finishedAt: start, status: .failed, error: error).isConsistent)
        XCTAssertFalse(make(finishedAt: start, status: .failed).isConsistent)
        XCTAssertFalse(make(status: .failed, error: error).isConsistent)
    }

    func testCancelledRecordRetainsCancellationAndFinish() {
        let cancellation = RunCancellation(reason: .userRequested, requestedAt: start)
        XCTAssertTrue(make(finishedAt: start, status: .cancelled, cancellation: cancellation).isConsistent)
        XCTAssertFalse(make(finishedAt: start, status: .cancelled).isConsistent)
    }

    func testRejectsConflictingPayloadsAndEarlierFinish() {
        let error = RunError(message: "failed")
        XCTAssertFalse(make(finishedAt: start, status: .running, error: error).isConsistent)
        XCTAssertFalse(make(finishedAt: start, status: .completed, cancellation: RunCancellation(reason: .unknown)).isConsistent)
        XCTAssertFalse(make(finishedAt: start.addingTimeInterval(-1), status: .failed, error: error).isConsistent)
    }

    func testRejectsInvalidMetricsTimestampsIdentityAndVersions() {
        XCTAssertFalse(make(metrics: .init(ttftMilliseconds: -1)).isConsistent)
        XCTAssertFalse(make(metrics: .init(ttftMilliseconds: 3, totalDurationMilliseconds: 2)).isConsistent)
        XCTAssertFalse(make(metrics: .init(inputTokenCount: -1)).isConsistent)
        XCTAssertFalse(make(startedAt: start, finishedAt: start.addingTimeInterval(-1)).isConsistent)
        XCTAssertFalse(make(model: " ").isConsistent)
        XCTAssertFalse(make(profileID: " ").isConsistent)
        XCTAssertFalse(make(profileVersion: 0).isConsistent)
        XCTAssertFalse(make(schemaVersion: 0).isConsistent)
    }

    private func make(
        model: String = "phi4-mini",
        profileID: String = "concise",
        profileVersion: Int = 1,
        schemaVersion: Int = 1,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        status: RunStatus = .running,
        metrics: RunMetrics = .init(),
        output: String? = nil,
        error: RunError? = nil,
        cancellation: RunCancellation? = nil
    ) -> RunRecord {
        RunRecord(
            model: model,
            profileID: profileID,
            profileVersion: profileVersion,
            schemaVersion: schemaVersion,
            endpointLocality: .local,
            startedAt: startedAt ?? start,
            finishedAt: finishedAt,
            status: status,
            metrics: metrics,
            output: output,
            error: error,
            cancellation: cancellation
        )
    }
}
