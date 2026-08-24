import Foundation

/// An actor-isolated client for Ollama's local HTTP API.
public actor OllamaClient: ModelProvider, EmbeddingProvider {
  /// Maximum size of one newline-delimited JSON response line. Ollama emits
  /// one JSON object per line; bounding a line prevents a malformed endpoint
  /// from growing an in-memory buffer without limit.
  public static let maxNDJSONLineBytes = 1_048_576

  public let endpoint: OllamaEndpoint
  private let session: URLSession
  private let timeout: TimeInterval
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  /// Creates a client using an injected URLSession, which is useful for tests and custom networking policies.
  public init(endpoint: OllamaEndpoint, session: URLSession, timeout: TimeInterval = 60) throws {
    guard timeout.isFinite, timeout > 0 else {
      throw OllamaClientError.invalidRequest("Timeout must be greater than zero")
    }
    self.endpoint = endpoint
    self.session = session
    self.timeout = timeout
    encoder = JSONEncoder()
    decoder = JSONDecoder()
  }

  /// Creates a client with a session configured with explicit request and resource timeouts.
  public init(endpoint: OllamaEndpoint, timeout: TimeInterval = 60) throws {
    guard timeout.isFinite, timeout > 0 else {
      throw OllamaClientError.invalidRequest("Timeout must be greater than zero")
    }
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    try self.init(
      endpoint: endpoint, session: URLSession(configuration: configuration), timeout: timeout)
  }

  public func fetchModels() async throws -> [OllamaModel] {
    let url = try endpoint.url(path: "/api/tags")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, _) = try await performDataRequest(request)
    guard let tags = try? decoder.decode(OllamaTagsResponse.self, from: data) else {
      throw OllamaClientError.decoding("Expected the /api/tags model list")
    }
    return tags.models
  }

  public func embed(model: String, input: String, dimensions: Int? = nil) async throws
    -> OllamaEmbedResponse
  {
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      dimensions.map({ $0 > 0 }) ?? true
    else {
      throw OllamaClientError.invalidRequest("Embedding model and input are required")
    }
    let body = OllamaEmbedRequest(model: model, input: input, dimensions: dimensions)
    var request = URLRequest(url: try endpoint.url(path: "/api/embed"))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.httpBody = try encoder.encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, _) = try await performDataRequest(request)
    do {
      let response = try decoder.decode(OllamaEmbedResponse.self, from: data)
      try validate(response, expectedModel: model, dimensions: dimensions)
      return response
    } catch let error as OllamaClientError {
      throw error
    } catch {
      throw OllamaClientError.decoding("Expected the /api/embed response")
    }
  }

  public func embed(model: String, inputs: [String], dimensions: Int? = nil) async throws
    -> OllamaEmbedResponse
  {
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !inputs.isEmpty,
      inputs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
      dimensions.map({ $0 > 0 }) ?? true
    else { throw OllamaClientError.invalidRequest("Embedding inputs are invalid") }
    let body = OllamaEmbedRequest(model: model, input: inputs, dimensions: dimensions)
    var request = URLRequest(url: try endpoint.url(path: "/api/embed"))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.httpBody = try encoder.encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, _) = try await performDataRequest(request)
    let response: OllamaEmbedResponse
    do { response = try decoder.decode(OllamaEmbedResponse.self, from: data) } catch {
      throw OllamaClientError.decoding("Expected the /api/embed response")
    }
    try validate(
      response, expectedModel: model, expectedCount: inputs.count, dimensions: dimensions)
    return response
  }

  private func validate(
    _ response: OllamaEmbedResponse, expectedModel: String, expectedCount: Int = 1,
    dimensions: Int? = nil
  ) throws {
    guard response.model == expectedModel,
      response.embeddings.count == expectedCount,
      let dimension = response.embeddings.first?.count, dimension > 0,
      dimensions == nil || dimensions == dimension,
      response.embeddings.allSatisfy({
        $0.count == dimension && $0.allSatisfy({ $0.isFinite }) && $0.contains(where: { $0 != 0 })
      })
    else { throw OllamaClientError.invalidResponse }
  }

  /// Starts a newline-delimited JSON generation stream.
  public nonisolated func generate(_ request: OllamaGenerateRequest) -> AsyncThrowingStream<
    OllamaGenerateChunk, Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task { [self] in
        do {
          try await self.stream(request, continuation: continuation)
          continuation.finish()
        } catch is CancellationError {
          continuation.finish(throwing: CancellationError())
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  /// Alias with an explicit name for call sites that want to distinguish streaming generation.
  public nonisolated func streamGenerate(_ request: OllamaGenerateRequest) -> AsyncThrowingStream<
    OllamaGenerateChunk, Error
  > {
    generate(request)
  }

  private func performDataRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw OllamaClientError.invalidResponse
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw httpError(status: httpResponse.statusCode, body: data)
      }
      return (data, httpResponse)
    } catch let error as OllamaClientError {
      throw error
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw map(error)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw OllamaClientError.transport(error.localizedDescription)
    }
  }

  private func stream(
    _ originalRequest: OllamaGenerateRequest,
    continuation: AsyncThrowingStream<OllamaGenerateChunk, Error>.Continuation
  ) async throws {
    guard !originalRequest.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw OllamaClientError.invalidRequest("A model name is required")
    }
    var requestBody = originalRequest
    requestBody.stream = true
    let data: Data
    do {
      data = try encoder.encode(requestBody)
    } catch {
      throw OllamaClientError.invalidRequest(error.localizedDescription)
    }
    let url = try endpoint.url(path: "/api/generate")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

    do {
      let (bytes, response) = try await session.bytes(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw OllamaClientError.invalidResponse
      }
      if !(200...299).contains(httpResponse.statusCode) {
        let body = try await collect(bytes: bytes)
        throw httpError(status: httpResponse.statusCode, body: body)
      }

      var line = Data()
      var didFinish = false

      func consume(_ rawLine: Data) throws {
        var normalized = rawLine
        while normalized.last == 13 || normalized.last == 32 || normalized.last == 9 {
          normalized.removeLast()
        }
        guard !normalized.isEmpty else { return }

        let chunk = try decodeChunk(from: normalized)
        // An error payload is authoritative even if the server incorrectly
        // marks it as terminal or sends it after a terminal frame.
        if let message = chunk.error,
          !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          throw OllamaClientError.server(message)
        }
        guard !didFinish else {
          throw OllamaClientError.protocolError("Received data after the terminal chunk.")
        }
        continuation.yield(chunk)
        didFinish = chunk.done == true
      }

      for try await byte in bytes {
        if Task.isCancelled { throw CancellationError() }
        if byte == 10 {
          try consume(line)
          line.removeAll(keepingCapacity: true)
        } else {
          guard line.count < Self.maxNDJSONLineBytes else {
            throw OllamaClientError.responseTooLarge(maxBytes: Self.maxNDJSONLineBytes)
          }
          line.append(byte)
        }
      }
      if !line.isEmpty {
        try consume(line)
      }
      guard didFinish else {
        throw OllamaClientError.protocolError("The stream ended before a terminal chunk.")
      }
    } catch let error as OllamaClientError {
      throw error
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw map(error)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw OllamaClientError.transport(error.localizedDescription)
    }
  }

  private func decodeChunk(from line: Data) throws -> OllamaGenerateChunk {
    do {
      return try decoder.decode(OllamaGenerateChunk.self, from: line)
    } catch {
      throw OllamaClientError.decoding(error.localizedDescription)
    }
  }

  private func collect(bytes: URLSession.AsyncBytes) async throws -> Data {
    var body = Data()
    for try await byte in bytes {
      if body.count >= 1_048_576 { break }
      body.append(byte)
    }
    return body
  }

  private func httpError(status: Int, body: Data) -> OllamaClientError {
    if let payload = try? decoder.decode(OllamaErrorPayload.self, from: body),
      !payload.error.isEmpty
    {
      return .httpStatus(code: status, message: payload.error)
    }
    return .httpStatus(code: status, message: nil)
  }

  private func map(_ error: URLError) -> OllamaClientError {
    if error.code == .timedOut { return .timedOut }
    return .transport(error.localizedDescription)
  }
}
