//
//  RunRecord.swift
//  PromptMAXX
//

import Foundation

nonisolated public enum EndpointLocality: String, Codable, Hashable, Sendable {
    case local
    case remote
    case unknown
}

nonisolated public enum RunStatus: String, Codable, Hashable, Sendable {
    case running
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        self != .running
    }
}

nonisolated public enum RunCancellationReason: String, Codable, Hashable, Sendable {
    case userRequested
    case promptReplaced
    case viewClosed
    case superseded
    case unknown
}

nonisolated public struct RunCancellation: Codable, Hashable, Sendable {
    public let reason: RunCancellationReason
    public let requestedAt: Date

    public init(reason: RunCancellationReason, requestedAt: Date = Date()) {
        self.reason = reason
        self.requestedAt = requestedAt
    }
}

nonisolated public struct RunError: Codable, Hashable, Sendable {
    public let domain: String?
    public let code: Int?
    public let message: String

    public init(domain: String? = nil, code: Int? = nil, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }
}

/// Measurements captured for one model execution. Values are optional because
/// a failed/cancelled run may end before a metric becomes available.
nonisolated public struct RunMetrics: Codable, Hashable, Sendable {
    public let ttftMilliseconds: Double?
    public let totalDurationMilliseconds: Double?
    public let inputTokenCount: Int?
    public let outputTokenCount: Int?

    public init(
        ttftMilliseconds: Double? = nil,
        totalDurationMilliseconds: Double? = nil,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil
    ) {
        self.ttftMilliseconds = ttftMilliseconds
        self.totalDurationMilliseconds = totalDurationMilliseconds
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
    }

    public var timeToFirstTokenMilliseconds: Double? { ttftMilliseconds }
    public var promptTokenCount: Int? { inputTokenCount }
    public var completionTokenCount: Int? { outputTokenCount }

    public var isValid: Bool {
        let durationsAreValid = [ttftMilliseconds, totalDurationMilliseconds]
            .compactMap { $0 }
            .allSatisfy { $0.isFinite && $0 >= 0 }
        let countsAreValid = [inputTokenCount, outputTokenCount]
            .compactMap { $0 }
            .allSatisfy { $0 >= 0 }
        let orderingIsValid: Bool = {
            guard let ttft = ttftMilliseconds,
                  let total = totalDurationMilliseconds else { return true }
            return ttft <= total
        }()
        return durationsAreValid && countsAreValid && orderingIsValid
    }
}

/// An immutable audit record for one prompt execution.
///
/// Invariants:
/// - `startedAt` is the beginning of the run; `finishedAt`, when present, is
///   not earlier than it.
/// - Terminal cancellation/failure information is retained instead of being
///   collapsed into a generic status.
/// - `schemaVersion` identifies the PromptSpec schema used for this run, while
///   `profileVersion` identifies the PromptProfile policy used to compile it.
/// - `output` is the model output only; no hidden chain-of-thought is stored.
nonisolated public struct RunRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let model: String
    public let modelVersion: String?
    public let profileID: String
    public let profileVersion: Int
    public let schemaVersion: Int
    public let endpointLocality: EndpointLocality
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: RunStatus
    public let metrics: RunMetrics
    public let output: String?
    public let error: RunError?
    public let cancellation: RunCancellation?

    public init(
        id: UUID = UUID(),
        model: String,
        modelVersion: String? = nil,
        profileID: String,
        profileVersion: Int,
        schemaVersion: Int,
        endpointLocality: EndpointLocality,
        startedAt: Date,
        finishedAt: Date? = nil,
        status: RunStatus,
        metrics: RunMetrics = .init(),
        output: String? = nil,
        error: RunError? = nil,
        cancellation: RunCancellation? = nil
    ) {
        self.id = id
        self.model = model
        self.modelVersion = modelVersion
        self.profileID = profileID
        self.profileVersion = profileVersion
        self.schemaVersion = schemaVersion
        self.endpointLocality = endpointLocality
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.metrics = metrics
        self.output = output
        self.error = error
        self.cancellation = cancellation
    }

    public var isConsistent: Bool {
        let timestampsAreValid = finishedAt.map { $0 >= startedAt } ?? true
        let identityIsValid = !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let versionsAreValid = profileVersion > 0 && schemaVersion > 0
        let statusPayloadIsValid: Bool
        switch status {
        case .running:
            statusPayloadIsValid = finishedAt == nil && error == nil && cancellation == nil
        case .completed:
            statusPayloadIsValid = finishedAt != nil && error == nil && cancellation == nil
        case .failed:
            statusPayloadIsValid = finishedAt != nil && error != nil && cancellation == nil
        case .cancelled:
            statusPayloadIsValid = finishedAt != nil && cancellation != nil
        }
        return identityIsValid && timestampsAreValid && versionsAreValid && metrics.isValid && statusPayloadIsValid
    }
}
