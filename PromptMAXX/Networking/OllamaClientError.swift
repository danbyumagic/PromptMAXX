import Foundation

/// Errors produced while communicating with an Ollama server.
nonisolated public enum OllamaClientError: Error, LocalizedError, Sendable, Equatable {
  case invalidEndpoint(String)
  case invalidPort(String)
  case invalidRequest(String)
  case invalidResponse
  case protocolError(String)
  case responseTooLarge(maxBytes: Int)
  case httpStatus(code: Int, message: String?)
  case server(String)
  case transport(String)
  case decoding(String)
  case timedOut

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint(let message):
      return String(localized: "Invalid Ollama endpoint: \(message)")
    case .invalidPort(let port):
      return String(localized: "Invalid Ollama port: \(port)")
    case .invalidRequest(let message):
      return String(localized: "Invalid Ollama request: \(message)")
    case .invalidResponse:
      return String(localized: "Ollama returned an invalid response.")
    case .protocolError(let message):
      return String(localized: "Ollama returned an incomplete or invalid stream: \(message)")
    case .responseTooLarge(let maxBytes):
      return String(localized: "Ollama returned a stream line larger than the \(maxBytes)-byte limit.")
    case .httpStatus(let code, let message):
      if let message, !message.isEmpty {
        return String(localized: "Ollama request failed (HTTP \(code)): \(message)")
      }
      return String(localized: "Ollama request failed (HTTP \(code)).")
    case .server(let message):
      return String(localized: "Ollama error: \(message)")
    case .transport(let message):
      return String(localized: "Could not connect to Ollama: \(message)")
    case .decoding(let message):
      return String(localized: "Could not read Ollama's response: \(message)")
    case .timedOut:
      return String(localized: "The Ollama request timed out.")
    }
  }
}
