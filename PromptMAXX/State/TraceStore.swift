import Foundation
import Observation

public enum TraceStoreState: Equatable, Sendable {
  case idle
  case loading
  case ready
  case failed
}

/// Main-actor application state for the trace browser.
@MainActor @Observable
public final class TraceStore {
  public let repository: TraceRepository
  public private(set) var traces: [RunTrace] = []
  public private(set) var state: TraceStoreState = .idle
  public private(set) var error: TraceRepositoryError?
  public private(set) var isBusy = false

  private var didAttemptLoad = false
  private var appendTail: Task<Bool, Never>?
  private var appendTailID: UUID?

  public init(repository: TraceRepository) {
    self.repository = repository
  }

  public convenience init() throws {
    self.init(repository: try TraceRepository())
  }

  public var isLoading: Bool { state == .loading }

  public func loadIfNeeded(force: Bool = false) async {
    guard !isBusy else {
      if force { error = .busy }
      return
    }
    guard force || !didAttemptLoad else { return }
    didAttemptLoad = true
    state = .loading
    isBusy = true
    error = nil
    defer { isBusy = false }

    do {
      traces = try await repository.load()
      state = .ready
    } catch let repositoryError as TraceRepositoryError {
      state = .failed
      error = repositoryError
    } catch let underlyingError {
      state = .failed
      error = TraceRepositoryError.unexpected(underlyingError.localizedDescription)
    }
  }

  public func retry() async {
    await loadIfNeeded(force: true)
  }

  @discardableResult
  public func append(_ trace: RunTrace) async -> Bool {
    await append(contentsOf: [trace])
  }

  /// Starts a serialized durability operation for terminal evidence.
  ///
  /// Callers must perform their run-token and cancellation checks immediately
  /// before invoking this method. Invocation is the append-start cutoff: once
  /// a batch is admitted here, later cancellation does not retract evidence
  /// that is queued or already being written.
  @discardableResult
  public func append(contentsOf newTraces: [RunTrace]) async -> Bool {
    guard !newTraces.isEmpty else { return true }
    // Appends are deliberately serialized. Repository writes can suspend while
    // awaiting disk I/O; rejecting a second UI callback during that suspension
    // would silently lose an otherwise valid terminal trace. This method does
    // not consult Task.isCancelled: admission above is the durability cutoff.
    let previous = appendTail
    let operationID = UUID()
    let operation = Task { @MainActor [weak self] in
      _ = await previous?.value
      guard let self else { return false }
      return await self.performAppend(contentsOf: newTraces)
    }
    appendTail = operation
    appendTailID = operationID
    let result = await operation.value
    if appendTailID == operationID {
      appendTail = nil
      appendTailID = nil
    }
    return result
  }

  private func performAppend(contentsOf newTraces: [RunTrace]) async -> Bool {
    // Browser mutations and initial loading may already own the store. A
    // terminal trace is durable evidence, so wait for that bounded operation
    // instead of dropping the trace as `busy`.
    while isBusy { await Task.yield() }
    await loadIfNeeded()
    while isBusy { await Task.yield() }
    guard state != .failed else { return false }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      // The batch has crossed the append-start cutoff. Do not attempt rollback
      // if cancellation or run supersession arrives while disk I/O suspends.
      try await repository.append(contentsOf: newTraces)
      traces.append(contentsOf: newTraces)
      traces = try await repository.load()
      state = .ready
      return true
    } catch let repositoryError as TraceRepositoryError {
      await record(repositoryError)
      return false
    } catch let underlyingError {
      state = .failed
      error = TraceRepositoryError.unexpected(underlyingError.localizedDescription)
      return false
    }
  }

  @discardableResult
  public func delete(id: UUID) async -> Bool {
    guard !isBusy else {
      error = .busy
      return false
    }
    await loadIfNeeded()
    guard state != .failed else { return false }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      try await repository.delete(id: id)
      traces.removeAll { $0.id == id }
      traces = try await repository.load()
      state = .ready
      return true
    } catch let repositoryError as TraceRepositoryError {
      await record(repositoryError)
      return false
    } catch let underlyingError {
      state = .failed
      error = TraceRepositoryError.unexpected(underlyingError.localizedDescription)
      return false
    }
  }

  @discardableResult
  public func retain(from: Date? = nil, to: Date? = nil) async -> Bool {
    guard !isBusy else {
      error = .busy
      return false
    }
    await loadIfNeeded()
    guard state != .failed else { return false }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      try await repository.retain(from: from, to: to)
      traces = traces.filter { Self.isIncluded($0.startedAt, from: from, to: to) }
      traces = try await repository.load()
      state = .ready
      return true
    } catch let repositoryError as TraceRepositoryError {
      await record(repositoryError)
      return false
    } catch let underlyingError {
      state = .failed
      error = TraceRepositoryError.unexpected(underlyingError.localizedDescription)
      return false
    }
  }

  public func clearError() {
    // A failed load/mutation remains failed until an explicit retry succeeds;
    // clearing a message must never make a corrupt store look healthy.
    guard state != .failed else { return }
    error = nil
  }

  public func filteredTraces(
    query: String = "", kind: TraceKind? = nil, status: RunStatus? = nil,
    model: String? = nil, from: Date? = nil, to: Date? = nil
  ) -> [RunTrace] {
    if let from, let to, from > to {
      error = .invalidDateRange(from: from, to: to)
      return []
    }
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidates = traces.filter { trace in
      (kind == nil || trace.kind == kind)
        && (status == nil || trace.status == status)
        && (model == nil || trace.model == model)
        && Self.isIncluded(trace.startedAt, from: from, to: to)
        && Self.matches(trace, query: normalizedQuery)
    }
    return candidates.sorted {
      if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
      return $0.startedAt > $1.startedAt
    }
  }

  public func exportJSON(redacted: Bool = true) async throws -> Data {
    try await repository.exportJSON(redacted: redacted)
  }

  public func exportMarkdown(redacted: Bool = true) async throws -> String {
    try await repository.exportMarkdown(redacted: redacted)
  }

  private func record(_ repositoryError: TraceRepositoryError) async {
    guard repositoryError.isRecoverableOperationError else {
      state = .failed
      error = repositoryError
      return
    }
    if case .busy = repositoryError {
      error = repositoryError
      return
    }
    do {
      // A recoverable conflict can indicate that another repository client
      // changed the file. Reconcile before exposing the error so the cache
      // never presents stale traces as canonical.
      traces = try await repository.load()
      state = .ready
      error = repositoryError
    } catch let reloadError as TraceRepositoryError {
      state = .failed
      error = reloadError
    } catch let underlyingError {
      state = .failed
      error = .unexpected(underlyingError.localizedDescription)
    }
  }

  private static func isIncluded(_ date: Date, from: Date?, to: Date?) -> Bool {
    if let from, date < from { return false }
    if let to, date > to { return false }
    return true
  }

  private static func matches(_ trace: RunTrace, query: String) -> Bool {
    guard !query.isEmpty else { return true }
    let searchable = [
      trace.id.uuidString, trace.kind.rawValue, trace.status.rawValue, trace.model,
      trace.profileID, trace.provider, trace.endpointLabel, trace.sourceText,
      trace.renderedInput, trace.compiledPrompt, trace.outputText, trace.error?.message
    ].compactMap { $0 }.joined(separator: " ")
      + " " + trace.events.map(\.summary).joined(separator: " ")
    return searchable.localizedCaseInsensitiveContains(query)
  }
}
