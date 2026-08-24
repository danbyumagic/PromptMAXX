import Foundation
import XCTest

@testable import PromptMAXX

final class OllamaClientTests: XCTestCase {
  private var session: URLSession!

  override func setUp() {
    super.setUp()
    URLProtocolMock.handler = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolMock.self]
    session = URLSession(configuration: configuration)
  }

  override func tearDown() {
    session.invalidateAndCancel()
    URLProtocolMock.handler = nil
    session = nil
    super.tearDown()
  }

  func testFetchModelsUsesTagsEndpointAndDecodesModels() async throws {
    let responseData = Data(#"{"models":[{"name":"llama3","model":"llama3"}]}"#.utf8)
    URLProtocolMock.handler = { request in
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.url?.path, "/api/tags")
      return URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/json"], body: responseData)
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "127.0.0.1"), session: session)
    let models = try await client.fetchModels()
    XCTAssertEqual(models.map(\.model), ["llama3"])

  }

  func testFetchModelsMapsNon2xxToTypedError() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 503, headers: ["Content-Type": "application/json"],
        body: Data(#"{"error":"server unavailable"}"#.utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    do {
      _ = try await client.fetchModels()
      XCTFail("Expected HTTP error")
    } catch let error as OllamaClientError {
      XCTAssertEqual(error, .httpStatus(code: 503, message: "server unavailable"))
    }
  }

  func testFetchModelsMapsMalformedJSONToDecodingError() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/json"], body: Data("not-json".utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    do {
      _ = try await client.fetchModels()
      XCTFail("Expected decoding error")
    } catch let error as OllamaClientError {
      guard case .decoding = error else { return XCTFail("Unexpected error: \(error)") }
    }
  }

  func testGenerateRequiresTerminalDoneChunk() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/x-ndjson"],
        body: Data(#"{"response":"partial"}"#.utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)

    do {
      _ = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))
      XCTFail("Expected an incomplete stream error")
    } catch let error as OllamaClientError {
      guard case .protocolError(let message) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertTrue(message.contains("terminal"))
    }
  }

  func testGenerateAcceptsValidTerminalChunkAndPreservesMetrics() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/x-ndjson"],
        body: Self.ndjson([
          #"{"response":"hello","done":false}"#,
          #"{"response":"","done":true,"total_duration":2000000,"eval_count":3}"#
        ]))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    let chunks = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))

    XCTAssertEqual(chunks.count, 2)
    XCTAssertEqual(chunks[0].response, "hello")
    XCTAssertEqual(chunks[1].done, true)
    XCTAssertEqual(chunks[1].evalCount, 3)
  }

  func testGenerateStreamedErrorWinsEvenWhenMarkedTerminal() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/x-ndjson"],
        body: Data(#"{"error":"model failed","done":true}"#.utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)

    do {
      _ = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))
      XCTFail("Expected streamed server error")
    } catch let error as OllamaClientError {
      XCTAssertEqual(error, .server("model failed"))
    }
  }

  func testGenerateRejectsDuplicateChunkAfterTerminal() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/x-ndjson"],
        body: Self.ndjson([
          #"{"response":"","done":true}"#,
          #"{"response":"late","done":false}"#
        ]))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)

    do {
      _ = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))
      XCTFail("Expected duplicate terminal protocol error")
    } catch let error as OllamaClientError {
      guard case .protocolError = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testGenerateRejectsOversizedNDJSONLine() async throws {
    URLProtocolMock.handler = { _ in
      let response = String(repeating: "x", count: OllamaClient.maxNDJSONLineBytes)
      return URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/x-ndjson"],
        body: Data("{\"response\":\"\(response)\"}\n".utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)

    do {
      _ = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))
      XCTFail("Expected oversized line error")
    } catch let error as OllamaClientError {
      XCTAssertEqual(error, .responseTooLarge(maxBytes: OllamaClient.maxNDJSONLineBytes))
    }
  }

  func testGenerateMapsCancelledTransportToCancellationError() async throws {
    URLProtocolMock.handler = { _ in throw URLError(.cancelled) }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)

    do {
      _ = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Cancellation is intentionally not surfaced as a transport failure.
    }
  }

  func testGenerateRejectsMalformedFinalFragment() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/x-ndjson"],
        body: Data("{\"response\":\"ok\",\"done\":false}\n{\"response\":".utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)

    do {
      _ = try await collect(client.generate(OllamaGenerateRequest(model: "m", prompt: "p")))
      XCTFail("Expected malformed final fragment")
    } catch let error as OllamaClientError {
      guard case .decoding = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testEmbedUsesOfficialRouteBodyAndValidatesResponse() async throws {
    URLProtocolMock.handler = { request in
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.url?.path, "/api/embed")
      let body = try XCTUnwrap(request.bodyDataForTesting)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["model"] as? String, "embeddinggemma")
      XCTAssertEqual(json["input"] as? String, "hello")
      return URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/json"],
        body: Data(#"{"model":"embeddinggemma","embeddings":[[0.5,0.5]]}"#.utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    let response = try await client.embed(model: "embeddinggemma", input: "hello", dimensions: 2)
    XCTAssertEqual(response.embeddings, [[0.5, 0.5]])
  }

  func testEmbedBatchBodyAndFourXXPayload() async throws {
    URLProtocolMock.handler = { request in
      let body = try XCTUnwrap(request.bodyDataForTesting)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["input"] as? [String], ["one", "two"])
      return URLProtocolMock.Response(
        status: 400, headers: [:], body: Data(#"{"error":"bad input"}"#.utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    do {
      _ = try await client.embed(model: "embeddinggemma", inputs: ["one", "two"])
      XCTFail("Expected HTTP error")
    } catch let error as OllamaClientError {
      XCTAssertEqual(error, .httpStatus(code: 400, message: "bad input"))
    }
  }

  func testEmbedRejectsMalformedCountWrongModelAndWrongDimension() async throws {
    let payloads = [
      "not-json",
      #"{"model":"embeddinggemma","embeddings":[]}"#,
      #"{"model":"other","embeddings":[[1,0]]}"#,
      #"{"model":"embeddinggemma","embeddings":[[1,0,0]]}"#,
    ]
    for payload in payloads {
      URLProtocolMock.handler = { _ in
        URLProtocolMock.Response(status: 200, headers: [:], body: Data(payload.utf8))
      }
      let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
      do {
        _ = try await client.embed(model: "embeddinggemma", input: "hello", dimensions: 2)
        XCTFail("Expected rejection")
      } catch let error as OllamaClientError {
        switch error {
        case .invalidResponse, .decoding: break
        default: XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }

  func testEmbedRejectsInvalidInputAndDimensions() async throws {
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    for dimensions in [0, -1] {
      await XCTAssertThrowsErrorAsync {
        _ = try await client.embed(model: "m", input: "x", dimensions: dimensions)
      }
    }
    await XCTAssertThrowsErrorAsync { _ = try await client.embed(model: " ", input: "x") }
    await XCTAssertThrowsErrorAsync { _ = try await client.embed(model: "m", input: " ") }
  }

  func testEmbedRejectsDimensionAndZeroVectorResponses() async throws {
    URLProtocolMock.handler = { _ in
      URLProtocolMock.Response(
        status: 200, headers: ["Content-Type": "application/json"],
        body: Data(#"{"model":"embeddinggemma","embeddings":[[0,0]]}"#.utf8))
    }
    let client = try OllamaClient(endpoint: OllamaEndpoint(host: "localhost"), session: session)
    do {
      _ = try await client.embed(model: "embeddinggemma", input: "hello", dimensions: 2)
      XCTFail("Expected invalid response")
    } catch let error as OllamaClientError { XCTAssertEqual(error, .invalidResponse) }
  }

  private static func ndjson(_ lines: [String]) -> Data {
    Data(lines.joined(separator: "\n").appending("\n").utf8)
  }

  private func collect(
    _ stream: AsyncThrowingStream<OllamaGenerateChunk, Error>
  ) async throws -> [OllamaGenerateChunk] {
    var chunks: [OllamaGenerateChunk] = []
    for try await chunk in stream { chunks.append(chunk) }
    return chunks
  }

}

private final class URLProtocolMock: URLProtocol {
  struct Response: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
  }

  nonisolated(unsafe) static var handler: ((URLRequest) throws -> Response)?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.unknown) }
      let result = try handler(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: result.headers
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: result.body)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

extension URLRequest {
  fileprivate var bodyDataForTesting: Data? {
    if let httpBody { return httpBody }
    guard let stream = httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: bufferSize)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @escaping () async throws -> T,
  file: StaticString = #filePath, line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected error", file: file, line: line)
  } catch {}
}
