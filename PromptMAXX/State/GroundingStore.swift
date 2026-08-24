import Foundation
import Observation

public enum GroundingStoreState: Equatable, Sendable {
  case idle
  case loading
  case ready
  case failed
}

/// Main-actor state for grounding workflows. Index and retrieval failures are
/// intentionally separate so a query problem cannot erase index diagnostics.
@MainActor @Observable
public final class GroundingStore {
  public let service: GroundingService
  public private(set) var state: GroundingStoreState = .idle
  public private(set) var sourceSummaries: [GroundingSourceSummary] = []
  public private(set) var selectedEmbeddingModel = ""
  public private(set) var selectedEmbeddingDimension: Int?
  public private(set) var indexProgress: GroundingIndexProgress?
  public private(set) var retrievalResult: GroundingRetrievalResult?
  public private(set) var indexError: GroundingError?
  public private(set) var retrievalError: GroundingError?
  public private(set) var isBusy = false

  private var didAttemptLoad = false
  private var indexOperationID: UUID?

  public init(service: GroundingService) {
    self.service = service
  }

  public convenience init(
    embeddingProvider: any EmbeddingProvider,
    chunker: GroundingChunker,
    retriever: GroundingRetriever,
    batchSize: Int = 16
  ) throws {
    let repository = try GroundingIndexRepository()
    let service = try GroundingService(
      embeddingProvider: embeddingProvider, repository: repository, chunker: chunker,
      retriever: retriever, batchSize: batchSize)
    self.init(service: service)
  }

  public var isLoading: Bool { state == .loading }

  public func loadIfNeeded(force: Bool = false) async {
    guard !isBusy else {
      if force { indexError = .busy }
      return
    }
    guard force || !didAttemptLoad else { return }
    didAttemptLoad = true
    state = .loading
    isBusy = true
    indexError = nil
    defer { isBusy = false }
    do {
      try await reloadCanonical()
      state = .ready
    } catch let error as GroundingError {
      state = .failed
      indexError = error
    } catch {
      state = .failed
      indexError = .read(error.localizedDescription)
    }
  }

  public func retry() async {
    await loadIfNeeded(force: true)
  }

  @discardableResult
  public func index(
    _ source: GroundingSource, embeddingModel: String, dimensions: Int? = nil
  ) async -> Bool {
    guard !isBusy else {
      indexError = .busy
      return false
    }
    await loadIfNeeded()
    guard state != .failed else { return false }
    let operationID = UUID()
    indexOperationID = operationID
    isBusy = true
    indexProgress = GroundingIndexProgress(completedChunks: 0, totalChunks: 0, sourceID: source.id)
    indexError = nil
    defer {
      if indexOperationID == operationID { indexOperationID = nil }
      isBusy = false
    }
    do {
      let progressSink = GroundingProgressSink(store: self, operationID: operationID)
      let progress: @Sendable (GroundingIndexProgress) -> Void = { value in
        Task { @MainActor in progressSink.update(value) }
      }
      _ = try await service.index(
        source: source, embeddingModel: embeddingModel, dimensions: dimensions, progress: progress)
      try await reloadCanonical()
      state = .ready
      return true
    } catch is CancellationError {
      indexError = .cancelled
      state = .ready
      return false
    } catch let error as GroundingError {
      await recordIndexError(error)
      return false
    } catch {
      state = .failed
      indexError = .read(error.localizedDescription)
      return false
    }
  }

  @discardableResult
  public func deleteSource(id: String) async -> Bool {
    guard !isBusy else {
      indexError = .busy
      return false
    }
    await loadIfNeeded()
    guard state != .failed else { return false }
    isBusy = true
    indexError = nil
    defer { isBusy = false }
    do {
      _ = try await service.deleteSource(id: id)
      try await reloadCanonical()
      state = .ready
      return true
    } catch let error as GroundingError {
      await recordIndexError(error)
      return false
    } catch {
      state = .failed
      indexError = .write(error.localizedDescription)
      return false
    }
  }

  @discardableResult
  public func clear() async -> Bool {
    guard !isBusy else {
      indexError = .busy
      return false
    }
    isBusy = true
    indexError = nil
    defer { isBusy = false }
    do {
      try await service.clear()
      sourceSummaries = []
      selectedEmbeddingModel = ""
      selectedEmbeddingDimension = nil
      retrievalResult = nil
      retrievalError = nil
      state = .ready
      didAttemptLoad = true
      return true
    } catch let error as GroundingError {
      await recordIndexError(error)
      return false
    } catch {
      state = .failed
      indexError = .write(error.localizedDescription)
      return false
    }
  }

  /// Destructive recovery for a user-confirmed corrupt/unsupported index.
  /// Failed-state UI should call this method, not `clear()`, when the user
  /// explicitly chooses to discard the unreadable file.
  @discardableResult
  public func discard() async -> Bool {
    guard !isBusy else {
      indexError = .busy
      return false
    }
    isBusy = true
    defer { isBusy = false }
    do {
      try await service.discardIndex()
      sourceSummaries = []
      selectedEmbeddingModel = ""
      selectedEmbeddingDimension = nil
      retrievalResult = nil
      indexError = nil
      retrievalError = nil
      didAttemptLoad = true
      state = .ready
      return true
    } catch let error as GroundingError {
      indexError = error
      state = .failed
      return false
    } catch {
      indexError = .write(error.localizedDescription)
      state = .failed
      return false
    }
  }

  public func retrieve(
    query: String, embeddingModel: String, dimensions: Int? = nil, topK: Int = 5,
    characterBudget: Int = .max
  ) async {
    guard !isBusy else {
      retrievalError = .busy
      return
    }
    await loadIfNeeded()
    guard state != .failed else { return }
    isBusy = true
    retrievalError = nil
    retrievalResult = nil
    defer { isBusy = false }
    do {
      retrievalResult = try await service.retrieve(
        query: query, embeddingModel: embeddingModel, dimensions: dimensions, topK: topK,
        characterBudget: characterBudget)
      if let result = retrievalResult {
        selectedEmbeddingModel = result.embeddingModel
        selectedEmbeddingDimension = result.dimension
      }
    } catch is CancellationError {
      retrievalError = .cancelled
    } catch let error as GroundingError {
      retrievalError = error
    } catch {
      retrievalError = .read(error.localizedDescription)
    }
  }

  public func clearErrors() {
    if state != .failed { indexError = nil }
    retrievalError = nil
  }

  fileprivate func updateIndexProgress(
    _ progress: GroundingIndexProgress, operationID: UUID
  ) {
    guard indexOperationID == operationID else { return }
    indexProgress = progress
  }

  private func recordIndexError(_ error: GroundingError) async {
    if error.isRecoverableOperationError {
      do {
        try await reloadCanonical()
        state = .ready
        indexError = error
      } catch let reloadError as GroundingError {
        state = .failed
        indexError = reloadError
      } catch {
        state = .failed
        indexError = .read(error.localizedDescription)
      }
    } else {
      state = .failed
      indexError = error
    }
  }

  private func reloadCanonical() async throws {
    sourceSummaries = try await service.listSources()
    let identity = try await service.indexIdentity()
    selectedEmbeddingModel = identity?.embeddingModel ?? ""
    selectedEmbeddingDimension = identity?.dimension
  }
}

private extension GroundingError {
  var isRecoverableOperationError: Bool {
    switch self {
    case .invalid, .dimensionMismatch, .notFound, .duplicateID,
        .invalidDimension, .embeddingModelMismatch, .embeddingResponseMismatch, .busy,
        .cancelled, .unsupportedFileType, .invalidUTF8:
      return true
    case .corruptIndex, .unsupportedVersion, .invalidURL, .directory, .read, .decode,
        .encode, .write, .replace, .invalidEnvelope:
      return false
    }
  }
}

@MainActor
private final class GroundingProgressSink {
  weak var store: GroundingStore?
  let operationID: UUID

  init(store: GroundingStore, operationID: UUID) {
    self.store = store
    self.operationID = operationID
  }

  func update(_ progress: GroundingIndexProgress) {
    store?.updateIndexProgress(progress, operationID: operationID)
  }
}
