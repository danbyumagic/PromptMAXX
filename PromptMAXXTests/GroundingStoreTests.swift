import Foundation
import XCTest

@testable import PromptMAXX

@MainActor
final class GroundingStoreTests: XCTestCase {
  func testStoreLifecycleIndexesAndRetrievesWithoutNetwork() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let provider = GroundingBatchEmbeddingProvider()
    let store = try makeStore(provider: provider, url: context.url)
    await store.loadIfNeeded()
    XCTAssertEqual(store.state, .ready)
    let source = try GroundingSource.text(name: "Doc", text: "alpha facts", id: "doc")
    let indexed = await store.index(source, embeddingModel: "embed-a")
    XCTAssertTrue(indexed)
    XCTAssertEqual(store.sourceSummaries.map(\.sourceID), ["doc"])

    await store.retrieve(query: "alpha", embeddingModel: "embed-a")
    XCTAssertNil(store.retrievalError)
    XCTAssertEqual(store.retrievalResult?.matches.first?.chunk.provenance.sourceID, "doc")
    XCTAssertTrue(store.retrievalResult?.envelope.prompt.contains("GROUNDING_DATA_BEGIN") == true)
  }

  func testIndexAndRetrievalErrorsAreSeparateAndRecoverable() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let store = try makeStore(provider: GroundingBatchEmbeddingProvider(), url: context.url)
    let source = try GroundingSource.text(name: "Doc", text: "alpha facts", id: "doc")
    let indexed = await store.index(source, embeddingModel: "embed-a")
    XCTAssertTrue(indexed)

    await store.retrieve(query: "alpha", embeddingModel: "embed-b")
    XCTAssertEqual(store.state, .ready)
    guard case .embeddingModelMismatch = store.retrievalError else {
      return XCTFail("Expected retrieval model mismatch")
    }
    XCTAssertEqual(store.sourceSummaries.map(\.sourceID), ["doc"])

    let mismatchedIndex = await store.index(source, embeddingModel: "embed-b")
    XCTAssertFalse(mismatchedIndex)
    XCTAssertEqual(store.state, .ready)
    guard case .embeddingModelMismatch = store.indexError else {
      return XCTFail("Expected index model mismatch")
    }
    let recovered = await store.index(source, embeddingModel: "embed-a")
    XCTAssertTrue(recovered)
    XCTAssertNil(store.indexError)
  }

  func testCorruptStoreFailsWithoutRecoveryOrByteReplacement() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let bytes = Data("not an index".utf8)
    try bytes.write(to: context.url, options: .atomic)
    let store = try makeStore(provider: GroundingBatchEmbeddingProvider(), url: context.url)
    await store.loadIfNeeded()
    XCTAssertEqual(store.state, .failed)
    XCTAssertNotNil(store.indexError)
    XCTAssertEqual(try Data(contentsOf: context.url), bytes)
    await store.retry()
    XCTAssertEqual(store.state, .failed)
    XCTAssertEqual(try Data(contentsOf: context.url), bytes)
    let discarded = await store.discard()
    XCTAssertTrue(discarded)
    XCTAssertEqual(store.state, .ready)
    XCTAssertNil(store.indexError)
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.url.path))
  }

  func testDefaultRepositoryURLUsesApplicationSupport() throws {
    let url = try GroundingIndexRepository.defaultURL(applicationName: "PromptMAXX-Test")
    XCTAssertTrue(url.path.contains("Application Support"))
    XCTAssertEqual(url.lastPathComponent, "grounding-index.json")
  }

  func testStoreCanDeleteAndClearSources() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let store = try makeStore(provider: GroundingBatchEmbeddingProvider(), url: context.url)
    let source = try GroundingSource.text(name: "Doc", text: "alpha facts", id: "doc")
    let indexed = await store.index(source, embeddingModel: "embed-a")
    XCTAssertTrue(indexed)
    let deleted = await store.deleteSource(id: "doc")
    XCTAssertTrue(deleted)
    XCTAssertTrue(store.sourceSummaries.isEmpty)
    let missingDelete = await store.deleteSource(id: "missing")
    XCTAssertFalse(missingDelete)
    XCTAssertEqual(store.state, .ready)
    let cleared = await store.clear()
    XCTAssertTrue(cleared)
  }

  func testRelaunchLoadRestoresIdentityAndClearResetsIt() async throws {
    let context = try makeContext()
    defer { try? FileManager.default.removeItem(at: context.directory) }
    let source = try GroundingSource.text(name: "Doc", text: "alpha facts", id: "doc")
    let firstStore = try makeStore(provider: GroundingBatchEmbeddingProvider(), url: context.url)
    let firstIndexed = await firstStore.index(source, embeddingModel: "embed-a")
    XCTAssertTrue(firstIndexed)
    XCTAssertEqual(firstStore.selectedEmbeddingModel, "embed-a")
    XCTAssertEqual(firstStore.selectedEmbeddingDimension, 2)

    // A new service/store instance must recover persisted identity without an
    // indexing call or provider request.
    let relaunched = try makeStore(provider: GroundingBatchEmbeddingProvider(), url: context.url)
    await relaunched.loadIfNeeded()
    XCTAssertEqual(relaunched.state, .ready)
    XCTAssertEqual(relaunched.selectedEmbeddingModel, "embed-a")
    XCTAssertEqual(relaunched.selectedEmbeddingDimension, 2)
    let cleared = await relaunched.clear()
    XCTAssertTrue(cleared)
    XCTAssertEqual(relaunched.selectedEmbeddingModel, "")
    XCTAssertNil(relaunched.selectedEmbeddingDimension)
  }

  private struct Context {
    let directory: URL
    let url: URL
  }

  private func makeContext() throws -> Context {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PromptMAXX-GroundingStore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return Context(directory: directory, url: directory.appendingPathComponent("index.json"))
  }

  private func makeStore(
    provider: GroundingBatchEmbeddingProvider, url: URL
  ) throws -> GroundingStore {
    let repository = try GroundingIndexRepository(url: url)
    let service = try GroundingService(
      embeddingProvider: provider, repository: repository,
      chunker: try GroundingChunker(size: 100, overlap: 0),
      retriever: try GroundingRetriever(lexicalWeight: 0), batchSize: 2)
    return GroundingStore(service: service)
  }
}
