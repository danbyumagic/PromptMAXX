import Foundation

/// A source of locally available language models and generated text.
nonisolated public protocol ModelProvider: Sendable {
  func fetchModels() async throws -> [OllamaModel]
  func generate(_ request: OllamaGenerateRequest) -> AsyncThrowingStream<OllamaGenerateChunk, Error>
}

nonisolated public protocol EmbeddingProvider: Sendable {
  func embed(model: String, input: String, dimensions: Int?) async throws -> OllamaEmbedResponse
  func embed(model: String, inputs: [String], dimensions: Int?) async throws -> OllamaEmbedResponse
}
