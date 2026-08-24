import Foundation

nonisolated public struct GroundingIndexProgress: Hashable, Sendable {
  public let completedChunks: Int
  public let totalChunks: Int
  public let sourceID: String

  public init(completedChunks: Int, totalChunks: Int, sourceID: String) {
    self.completedChunks = completedChunks
    self.totalChunks = totalChunks
    self.sourceID = sourceID
  }
}

nonisolated public struct GroundingRetrievalResult: Hashable, Sendable {
  public let query: String
  public let embeddingModel: String
  public let dimension: Int
  public let matches: [GroundingMatch]
  public let envelope: GroundingContextEnvelope

  public init(
    query: String, embeddingModel: String, dimension: Int, matches: [GroundingMatch],
    envelope: GroundingContextEnvelope
  ) {
    self.query = query
    self.embeddingModel = embeddingModel
    self.dimension = dimension
    self.matches = matches
    self.envelope = envelope
  }
}

/// Coordinates bounded embedding, identity-safe persistence, and retrieval.
/// It never persists a partially indexed source.
public actor GroundingService {
  private let embeddingProvider: any EmbeddingProvider
  private let repository: GroundingIndexRepository
  private let chunker: GroundingChunker
  private let retriever: GroundingRetriever
  private let batchSize: Int

  public init(
    embeddingProvider: any EmbeddingProvider,
    repository: GroundingIndexRepository,
    chunker: GroundingChunker,
    retriever: GroundingRetriever,
    batchSize: Int = 16
  ) throws {
    guard batchSize > 0 else { throw GroundingError.invalid("Embedding batch size is invalid") }
    self.embeddingProvider = embeddingProvider
    self.repository = repository
    self.chunker = chunker
    self.retriever = retriever
    self.batchSize = batchSize
  }

  /// Provides an in-memory benchmark runner over this service's injected
  /// provider. Benchmark results are separate from the persisted app index.
  public func makeBenchmarkRunner(
    clock: @escaping @Sendable () -> Date = { Date() }
  ) -> GroundingBenchmarkRunner {
    GroundingBenchmarkRunner(embeddingProvider: embeddingProvider, clock: clock)
  }

  public func index(
    source: GroundingSource,
    embeddingModel: String,
    dimensions: Int? = nil,
    progress: (@Sendable (GroundingIndexProgress) -> Void)? = nil
  ) async throws -> GroundingIndex {
    try source.validate()
    let model = embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else { throw GroundingError.invalid("Embedding model is required") }
    if let dimensions, dimensions <= 0 { throw GroundingError.invalidDimension }

    let previous = try await repository.loadIndex()
    if let previous {
      guard previous.embeddingModel == model else {
        throw GroundingError.embeddingModelMismatch(
          expected: previous.embeddingModel, actual: model)
      }
      if let dimensions, dimensions != previous.dimension {
        throw GroundingError.dimensionMismatch
      }
    }

    let chunks = chunker.chunks(from: source)
    guard !chunks.isEmpty else { throw GroundingError.invalid("Source has no indexable chunks") }
    progress?(GroundingIndexProgress(completedChunks: 0, totalChunks: chunks.count, sourceID: source.id))

    var embeddedEntries: [GroundingIndexEntry] = []
    embeddedEntries.reserveCapacity(chunks.count)
    var expectedDimension = previous?.dimension ?? dimensions
    for start in stride(from: 0, to: chunks.count, by: batchSize) {
      try Task.checkCancellation()
      let end = min(chunks.count, start + batchSize)
      let batch = Array(chunks[start..<end])
      let response = try await embeddingProvider.embed(
        model: model, inputs: batch.map(\.text), dimensions: expectedDimension)
      try validate(response, model: model, count: batch.count, dimensions: expectedDimension)
      let dimension = response.embeddings[0].count
      if let expectedDimension, expectedDimension != dimension {
        throw GroundingError.dimensionMismatch
      }
      expectedDimension = dimension
      for (chunk, values) in zip(batch, response.embeddings) {
        embeddedEntries.append(
          try GroundingIndexEntry(chunk: chunk, embedding: GroundingEmbedding(values)))
      }
      progress?(GroundingIndexProgress(
        completedChunks: end, totalChunks: chunks.count, sourceID: source.id))
    }

    try Task.checkCancellation()
    guard let dimension = expectedDimension else { throw GroundingError.invalidDimension }
    let retained = previous?.entries.filter { $0.chunk.provenance.sourceID != source.id } ?? []
    let index = try GroundingIndex(
      embeddingModel: model, dimension: dimension, entries: retained + embeddedEntries)
    try Task.checkCancellation()
    try await repository.save(index)
    return index
  }

  public func deleteSource(id: String) async throws -> GroundingIndex {
    guard let previous = try await repository.loadIndex() else { throw GroundingError.notFound }
    let retained = previous.entries.filter { $0.chunk.provenance.sourceID != id }
    guard retained.count != previous.entries.count else { throw GroundingError.notFound }
    let index = try GroundingIndex(
      embeddingModel: previous.embeddingModel, dimension: previous.dimension, entries: retained)
    try await repository.save(index)
    return index
  }

  public func delete(sourceID: String) async throws -> GroundingIndex {
    try await deleteSource(id: sourceID)
  }

  public func clearIndex() async throws {
    try await repository.clear()
  }

  public func clear() async throws {
    try await clearIndex()
  }

  /// Explicitly discards the persisted index, including a corrupt or
  /// unsupported file. Callers should expose this only behind confirmation.
  public func discardIndex() async throws {
    try await repository.discard()
  }

  public func discard() async throws {
    try await discardIndex()
  }

  public func listSources() async throws -> [GroundingSourceSummary] {
    guard let index = try await repository.loadIndex() else { return [] }
    let grouped = Dictionary(grouping: index.entries) { $0.chunk.provenance.sourceID }
    return grouped.compactMap { sourceID, entries in
      guard let first = entries.first else { return nil }
      return GroundingSourceSummary(
        sourceID: sourceID, sourceName: first.chunk.provenance.sourceName,
        sourceVersion: first.chunk.sourceVersion, chunkCount: entries.count)
    }.sorted {
      $0.sourceName == $1.sourceName ? $0.sourceID < $1.sourceID
        : $0.sourceName.localizedStandardCompare($1.sourceName) == .orderedAscending
    }
  }

  public func indexIdentity() async throws -> GroundingIndexIdentity? {
    try await repository.loadIndex().map {
      GroundingIndexIdentity(embeddingModel: $0.embeddingModel, dimension: $0.dimension)
    }
  }

  public func retrieve(
    query: String,
    embeddingModel: String,
    dimensions: Int? = nil,
    topK: Int = 5,
    characterBudget: Int = .max
  ) async throws -> GroundingRetrievalResult {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedModel = embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty, !normalizedModel.isEmpty, topK > 0, characterBudget > 0 else {
      throw GroundingError.invalid("Retrieval query, model, and limits are required")
    }
    guard let index = try await repository.loadIndex(), !index.entries.isEmpty else {
      throw GroundingError.notFound
    }
    guard index.embeddingModel == normalizedModel else {
      throw GroundingError.embeddingModelMismatch(
        expected: index.embeddingModel, actual: normalizedModel)
    }
    if let dimensions, dimensions != index.dimension { throw GroundingError.dimensionMismatch }
    try Task.checkCancellation()
    let response = try await embeddingProvider.embed(
      model: normalizedModel, input: normalizedQuery, dimensions: index.dimension)
    try validate(response, model: normalizedModel, count: 1, dimensions: index.dimension)
    let queryEmbedding = try GroundingEmbedding(response.embeddings[0])
    let matches = try retriever.retrieve(
      query: normalizedQuery, embedding: queryEmbedding, entries: index.entries, topK: topK,
      characterBudget: characterBudget)
    let envelope = try GroundingContextEnvelope(question: normalizedQuery, matches: matches)
    return GroundingRetrievalResult(
      query: normalizedQuery, embeddingModel: index.embeddingModel, dimension: index.dimension,
      matches: matches, envelope: envelope)
  }

  private func validate(
    _ response: OllamaEmbedResponse, model: String, count: Int, dimensions: Int?
  ) throws {
    guard response.model == model, response.embeddings.count == count,
      let dimension = response.embeddings.first?.count, dimension > 0
    else { throw GroundingError.embeddingResponseMismatch }
    if let dimensions, dimensions != dimension { throw GroundingError.dimensionMismatch }
    guard response.embeddings.allSatisfy({
      $0.count == dimension && $0.allSatisfy(\.isFinite) && $0.contains(where: { $0 != 0 })
    }) else { throw GroundingError.embeddingResponseMismatch }
  }
}
