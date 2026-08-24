import Foundation
import XCTest

@testable import PromptMAXX

actor GroundingBatchEmbeddingProvider: EmbeddingProvider {
  private let dimension: Int
  private let delayNanoseconds: UInt64
  private var batches: [[String]] = []

  init(dimension: Int = 2, delayNanoseconds: UInt64 = 0) {
    self.dimension = dimension
    self.delayNanoseconds = delayNanoseconds
  }

  func embed(model: String, input: String, dimensions: Int?) async throws -> OllamaEmbedResponse {
    try await embed(model: model, inputs: [input], dimensions: dimensions)
  }

  func embed(model: String, inputs: [String], dimensions: Int?) async throws -> OllamaEmbedResponse {
    if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
    batches.append(inputs)
    let vectors = inputs.map { input -> [Double] in
      if dimension == 1 { return [max(0.1, Double(input.count))] }
      return input.localizedCaseInsensitiveContains("alpha") ? [1, 0] : [0, 1]
    }
    return OllamaEmbedResponse(
      model: model, embeddings: vectors, totalDuration: nil, loadDuration: nil,
      promptEvalCount: nil)
  }

  func recordedBatches() -> [[String]] { batches }
}

final class GroundingServiceTests: XCTestCase {
  func testIndexUsesBoundedBatchesAndPersistsModelIdentity() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let provider = GroundingBatchEmbeddingProvider()
    let service = try makeService(provider: provider, url: context.url, chunkSize: 4, batchSize: 2)
    let source = try GroundingSource.text(name: "Doc", text: "abcdefghij", id: "doc")

    let index = try await service.index(source: source, embeddingModel: "embed-a")
    XCTAssertEqual(index.embeddingModel, "embed-a")
    XCTAssertEqual(index.dimension, 2)
    XCTAssertEqual(index.entries.count, 3)
    let batches = await provider.recordedBatches()
    XCTAssertEqual(batches.map(\.count), [2, 1])
    let persisted = try await context.repository.loadIndex()
    XCTAssertEqual(persisted, index)
  }

  func testSecondModelIsRejectedAndReplacementDoesNotDuplicateChunks() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let provider = GroundingBatchEmbeddingProvider()
    let service = try makeService(provider: provider, url: context.url, chunkSize: 5, batchSize: 3)
    let first = try GroundingSource.text(name: "Doc", text: "abcdefghij", id: "same")
    let second = try GroundingSource.text(name: "Doc", text: "klmnopqrst", id: "same")
    _ = try await service.index(source: first, embeddingModel: "embed-a")
    let oldBytes = try Data(contentsOf: context.url)

    do {
      _ = try await service.index(source: first, embeddingModel: "embed-b")
      XCTFail("Expected model identity mismatch")
    } catch let error as GroundingError {
      guard case .embeddingModelMismatch = error else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(try Data(contentsOf: context.url), oldBytes)

    let replaced = try await service.index(source: second, embeddingModel: "embed-a")
    XCTAssertEqual(replaced.entries.count, 2)
    XCTAssertEqual(Set(replaced.entries.map { $0.chunk.provenance.sourceID }), ["same"])
    XCTAssertEqual(Set(replaced.entries.map(\.id)).count, replaced.entries.count)
  }

  func testCancellationBeforeSaveLeavesPreviousBytesUntouched() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let provider = GroundingBatchEmbeddingProvider(delayNanoseconds: 200_000_000)
    let service = try makeService(provider: provider, url: context.url, chunkSize: 20, batchSize: 2)
    let old = try GroundingSource.text(name: "Old", text: "old content", id: "old")
    _ = try await service.index(source: old, embeddingModel: "embed-a")
    let oldBytes = try Data(contentsOf: context.url)
    let replacement = try GroundingSource.text(name: "New", text: "new content", id: "new")

    let task = Task { try await service.index(source: replacement, embeddingModel: "embed-a") }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected: the service checks cancellation before persistence.
    }
    XCTAssertEqual(try Data(contentsOf: context.url), oldBytes)
    let sources = try await service.listSources()
    XCTAssertEqual(sources.map(\.sourceID), ["old"])
  }

  func testDeleteClearAndRetrievalPreserveProvenanceEnvelope() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let provider = GroundingBatchEmbeddingProvider()
    let service = try makeService(provider: provider, url: context.url, chunkSize: 100, batchSize: 2)
    let source = try GroundingSource.text(
      name: "Facts", text: "alpha grounding facts", id: "facts")
    _ = try await service.index(source: source, embeddingModel: "embed-a")

    let result = try await service.retrieve(query: "alpha", embeddingModel: "embed-a")
    XCTAssertEqual(result.embeddingModel, "embed-a")
    XCTAssertEqual(result.matches.first?.chunk.provenance.sourceID, "facts")
    XCTAssertTrue(result.envelope.prompt.contains("GROUNDING_DATA_BEGIN"))
    XCTAssertTrue(result.envelope.prompt.contains("Facts"))

    _ = try await service.deleteSource(id: "facts")
    let sources = try await service.listSources()
    XCTAssertTrue(sources.isEmpty)
    try await service.clear()
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.url.path))
  }

  func testInvalidRetrievalDoesNotCallEmbeddingProvider() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let provider = GroundingBatchEmbeddingProvider()
    let service = try makeService(provider: provider, url: context.url, chunkSize: 100, batchSize: 2)
    let source = try GroundingSource.text(name: "Facts", text: "alpha facts", id: "facts")
    _ = try await service.index(source: source, embeddingModel: "embed-a")
    let countBefore = (await provider.recordedBatches()).count

    do {
      _ = try await service.retrieve(
        query: "   ", embeddingModel: "   ", topK: 0, characterBudget: 0)
      XCTFail("Expected invalid retrieval request")
    } catch let error as GroundingError {
      guard case .invalid = error else { return XCTFail("Unexpected error: \(error)") }
    }
    let countAfter = (await provider.recordedBatches()).count
    XCTAssertEqual(countAfter, countBefore)
  }

  func testRepositoryRejectsTamperedIdentityAndPreservesBytes() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let source = try GroundingSource.text(name: "Doc", text: "alpha", id: "doc")
    let entry = try GroundingIndexEntry(
      chunk: try GroundingChunker(size: 50, overlap: 0).chunks(from: source)[0],
      embedding: GroundingEmbedding([1, 0]))
    let index = try GroundingIndex(embeddingModel: "embed-a", dimension: 2, entries: [entry])
    try await context.repository.save(index)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: context.url)) as? [String: Any])
    object["dimension"] = 3
    let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try tampered.write(to: context.url, options: .atomic)

    do {
      _ = try await context.repository.loadIndex()
      XCTFail("Expected dimension mismatch")
    } catch let error as GroundingError {
      guard case .dimensionMismatch = error else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(try Data(contentsOf: context.url), tampered)
  }

  func testSourceConstructionAndImporterUseStableIDsAndValidateFiles() throws {
    let first = try GroundingSource.text(name: "Doc", text: "same")
    let second = try GroundingSource.text(name: "Doc", text: "same")
    XCTAssertEqual(first.id, second.id)
    XCTAssertNotEqual(first.id, (try GroundingSource.text(name: "Doc", text: "changed")).id)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("notes.md")
    try Data("hello markdown".utf8).write(to: file)
    let imported = try GroundingSourceImporter.importFile(at: file)
    XCTAssertEqual(imported.name, "notes")
    XCTAssertEqual(imported.text, "hello markdown")
    XCTAssertThrowsError(try GroundingSourceImporter.importFile(
      at: directory.appendingPathComponent("notes.pdf")))
  }

  func testSourceImporterAcceptsInclusiveSizeLimitAndRejectsOversizeFiles() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PromptMAXX-GroundingImporter-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let boundaryURL = directory.appendingPathComponent("boundary.txt")
    let boundaryData = Data(repeating: 0x61, count: GroundingSourceImporter.maxFileBytes)
    try boundaryData.write(to: boundaryURL)
    let boundary = try GroundingSourceImporter.importFile(at: boundaryURL)
    XCTAssertEqual(boundary.text.utf8.count, GroundingSourceImporter.maxFileBytes)

    let oversizedURL = directory.appendingPathComponent("oversized.md")
    var oversizedData = boundaryData
    oversizedData.append(0x61)
    try oversizedData.write(to: oversizedURL)
    do {
      _ = try GroundingSourceImporter.importFile(at: oversizedURL)
      XCTFail("Expected the importer to reject a file over the inclusive limit")
    } catch let error as GroundingError {
      guard case .invalid(let message) = error else {
        return XCTFail("Unexpected oversize error: \(error)")
      }
      XCTAssertTrue(message.contains("too large"))
    }
  }

  private struct Context {
    let directory: URL
    let url: URL
    let repository: GroundingIndexRepository
  }

  private func makeContext() throws -> Context {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PromptMAXX-Grounding-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("index.json")
    return Context(directory: directory, url: url, repository: try GroundingIndexRepository(url: url))
  }

  private func makeService(
    provider: GroundingBatchEmbeddingProvider, url: URL, chunkSize: Int, batchSize: Int
  ) throws -> GroundingService {
    try GroundingService(
      embeddingProvider: provider, repository: try GroundingIndexRepository(url: url),
      chunker: try GroundingChunker(size: chunkSize, overlap: 0),
      retriever: try GroundingRetriever(lexicalWeight: 0), batchSize: batchSize)
  }
}
