import Foundation
import Darwin

/// The address of an Ollama HTTP server.
nonisolated public struct OllamaEndpoint: Hashable, Sendable {
  public let host: String
  public let port: Int
  public let baseURL: URL

  public init(host rawHost: String, port: Int = 11_434) throws {
    guard (1...65_535).contains(port) else {
      throw OllamaClientError.invalidPort(String(port))
    }

    let normalizedHost = try Self.validatedHost(rawHost)
    var components = URLComponents()
    components.scheme = "http"
    // URLComponents expects IPv6 literals to be bracketed when assigned as a host.
    components.host = normalizedHost.contains(":") ? "[\(normalizedHost)]" : normalizedHost
    components.port = port

    guard let url = components.url else {
      throw OllamaClientError.invalidEndpoint("Unable to construct a URL")
    }

    host = normalizedHost
    self.port = port
    baseURL = url
  }

  /// A convenience initializer that accepts the decimal port representation used by settings forms.
  public init(host: String, port: String) throws {
    guard !port.isEmpty, port.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      throw OllamaClientError.invalidPort(port)
    }
    guard let value = Int(port), (1...65_535).contains(value) else {
      throw OllamaClientError.invalidPort(port)
    }
    try self.init(host: host, port: value)
  }

  public var isLoopback: Bool {
    let candidate = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    if candidate == "localhost" || candidate == "localhost." || candidate == "::1" {
      return true
    }

    if let bytes = Self.ipv4Bytes(candidate) {
      return bytes.first == 127
    }
    if let bytes = Self.ipv6Bytes(candidate) {
      let isIPv6Loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
      let isIPv4MappedLoopback =
        bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        && bytes[12] == 127
      return isIPv6Loopback || isIPv4MappedLoopback
    }
    return false
  }

  /// Builds a URL rooted at this endpoint without force-unwrapping URLComponents.
  public func url(path: String) throws -> URL {
    guard !path.isEmpty, path.first == "/", !path.contains("?") && !path.contains("#") else {
      throw OllamaClientError.invalidEndpoint(
        "Path must be an absolute path without a query or fragment")
    }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    components?.path = path
    guard let url = components?.url else {
      throw OllamaClientError.invalidEndpoint("Unable to construct a URL")
    }
    return url
  }

  private static func validatedHost(_ rawHost: String) throws -> String {
    guard rawHost == rawHost.trimmingCharacters(in: .whitespacesAndNewlines), !rawHost.isEmpty
    else {
      throw OllamaClientError.invalidEndpoint(
        "Host must not contain leading or trailing whitespace")
    }
    guard !rawHost.contains(where: { $0.isWhitespace || $0.isNewline }),
      !rawHost.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      !rawHost.contains(where: { "/\\?#%".contains($0) })
    else {
      throw OllamaClientError.invalidEndpoint("Host contains whitespace or URL punctuation")
    }
    guard !rawHost.contains("://") else {
      throw OllamaClientError.invalidEndpoint("Host must not include a URL scheme")
    }

    let candidate: String
    let wasBracketed = rawHost.first == "[" || rawHost.last == "]"
    if wasBracketed {
      guard rawHost.first == "[", rawHost.last == "]", rawHost.count > 2 else {
        throw OllamaClientError.invalidEndpoint("Malformed IPv6 host")
      }
      candidate = String(rawHost.dropFirst().dropLast())
    } else {
      candidate = rawHost
    }

    guard !candidate.isEmpty else {
      throw OllamaClientError.invalidEndpoint("Host must not be empty")
    }
    if wasBracketed, !candidate.contains(":") {
      throw OllamaClientError.invalidEndpoint("Only IPv6 hosts may use brackets")
    }
    if candidate.contains(":") {
      guard Self.ipv6Bytes(candidate) != nil else {
        throw OllamaClientError.invalidEndpoint("Malformed IPv6 host")
      }
      return candidate
    }

    guard candidate.utf8.count <= 253 else {
      throw OllamaClientError.invalidEndpoint("Host is too long")
    }
    let hasTrailingDot = candidate.last == "."
    let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
    guard !labels.isEmpty else {
      throw OllamaClientError.invalidEndpoint("Malformed host")
    }
    if hasTrailingDot {
      guard labels.last?.isEmpty == true, labels.count > 1 else {
        throw OllamaClientError.invalidEndpoint("Malformed host")
      }
    }
    let addressLabels = hasTrailingDot ? labels.dropLast() : labels[...]
    if addressLabels.count == 4, addressLabels.allSatisfy({ $0.allSatisfy { $0.isNumber } }) {
      guard Self.ipv4Bytes(candidate) != nil else {
        throw OllamaClientError.invalidEndpoint("Malformed IPv4 host")
      }
    }
    for label in addressLabels {
      guard let first = label.first, let last = label.last,
        !label.isEmpty, label.utf8.count <= 63,
        first.isASCII && last.isASCII,
        first.isNumber || first.isLetter,
        last.isNumber || last.isLetter,
        label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
      else {
        throw OllamaClientError.invalidEndpoint("Malformed host")
      }
    }
    return candidate
  }

  private static func ipv4Bytes(_ address: String) -> [UInt8]? {
    var parsed = in_addr()
    let result = address.withCString { inet_pton(AF_INET, $0, &parsed) }
    guard result == 1 else { return nil }
    return withUnsafeBytes(of: &parsed) { Array($0) }
  }

  private static func ipv6Bytes(_ address: String) -> [UInt8]? {
    var parsed = in6_addr()
    let result = address.withCString { inet_pton(AF_INET6, $0, &parsed) }
    guard result == 1 else { return nil }
    return withUnsafeBytes(of: &parsed) { Array($0) }
  }
}
