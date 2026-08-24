import CryptoKit
import Foundation

nonisolated public enum GroundingError: Error, LocalizedError, Sendable, Equatable {
  case invalid(String)
  case dimensionMismatch
  case corruptIndex
  case unsupportedVersion
  case notFound
  case duplicateID
  case invalidDimension
  case invalidURL, directory
  case read(String)
  case decode(String)
  case encode(String)
  case write(String)
  case replace(String)
  case invalidEnvelope
  case embeddingModelMismatch(expected: String, actual: String)
  case embeddingResponseMismatch
  case busy
  case unsupportedFileType
  case invalidUTF8
  case cancelled
  public var errorDescription: String? {
    switch self {
    case .invalid(let s): return s
    case .dimensionMismatch: return "Embedding dimensions do not match the persisted index."
    case .corruptIndex: return "The grounding index is corrupt."
    case .unsupportedVersion: return "The grounding index version is unsupported."
    case .notFound: return "The grounding source was not found."
    case .duplicateID: return "The grounding index contains a duplicate chunk ID."
    case .invalidDimension: return "The embedding dimension is invalid."
    case .invalidURL: return "The grounding repository URL is invalid."
    case .directory: return "The grounding repository directory could not be created."
    case .read(let s): return "The grounding index could not be read: \(s)"
    case .decode(let s): return "The grounding index could not be decoded: \(s)"
    case .encode(let s): return "The grounding index could not be encoded: \(s)"
    case .write(let s): return "The grounding index could not be written: \(s)"
    case .replace(let s): return "The grounding index could not be replaced: \(s)"
    case .invalidEnvelope: return "The grounding index contains invalid entries."
    case .embeddingModelMismatch(let expected, let actual):
      return "Embedding model mismatch: index uses \(expected), request uses \(actual)."
    case .embeddingResponseMismatch: return "The embedding provider returned an invalid response."
    case .busy: return "Grounding is busy with another operation."
    case .unsupportedFileType: return "Only UTF-8 text and Markdown files are supported."
    case .invalidUTF8: return "The source file is not valid UTF-8."
    case .cancelled: return "Grounding was cancelled before the index was saved."
    }
  }
}

nonisolated public struct GroundingSource: Codable, Hashable, Sendable, Identifiable {
  public static let currentVersion = 1
  public let id: String
  public let version: Int
  public let name: String
  public let text: String
  public var contentHash: String { GroundingHash.digest(text) }
  public init(id: String, version: Int = 1, name: String, text: String) throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      version == Self.currentVersion,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw GroundingError.invalid("Source fields are required") }
    self.id = id
    self.version = version
    self.name = name
    self.text = text
  }
  public func validate() throws {
    _ = try GroundingSource(id: id, version: version, name: name, text: text)
  }

  /// Builds a text source with a deterministic content-derived identity unless
  /// an explicit identity is supplied by the caller.
  public static func text(
    name: String, text: String, version: Int = 1, id: String? = nil
  ) throws -> GroundingSource {
    let stableID = id ?? GroundingHash.digest(name + "\u{1F}" + text)
    return try GroundingSource(id: stableID, version: version, name: name, text: text)
  }

  /// Markdown is intentionally kept as UTF-8 text in this foundation layer.
  public static func markdown(
    name: String, text: String, version: Int = 1, id: String? = nil
  ) throws -> GroundingSource {
    try self.text(name: name, text: text, version: version, id: id)
  }
}

/// Small file importer for UTF-8 text and Markdown sources. PDF parsing is
/// deliberately outside this layer.
nonisolated public enum GroundingSourceImporter {
  public static let supportedExtensions: Set<String> = ["txt", "md", "markdown"]
  public static let maxFileBytes = 10 * 1024 * 1024

  public static func importFile(at url: URL, id: String? = nil) throws -> GroundingSource {
    let ext = url.pathExtension.lowercased()
    guard supportedExtensions.contains(ext) else { throw GroundingError.unsupportedFileType }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let fileSize = values.fileSize, fileSize > Self.maxFileBytes {
        throw GroundingError.invalid(Self.fileTooLargeMessage)
      }
    } catch let error as GroundingError {
      throw error
    } catch {
      throw GroundingError.read(error.localizedDescription)
    }
    let data: Data
    do { data = try Data(contentsOf: url) } catch {
      throw GroundingError.read(error.localizedDescription)
    }
    guard data.count <= Self.maxFileBytes else {
      throw GroundingError.invalid(Self.fileTooLargeMessage)
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw GroundingError.invalidUTF8
    }
    let name = url.deletingPathExtension().lastPathComponent
    return ext == "txt"
      ? try GroundingSource.text(name: name, text: text, id: id)
      : try GroundingSource.markdown(name: name, text: text, id: id)
  }

  private static var fileTooLargeMessage: String {
    "The source file is too large. Choose a UTF-8 text or Markdown file no larger than \(ByteCountFormatter.string(fromByteCount: Int64(maxFileBytes), countStyle: .file))."
  }

  /// Performs the bounded file read away from the caller's actor. The
  /// synchronous API remains available for non-UI callers and deterministic
  /// tests; SwiftUI should use this async entry point.
  public static func importFileAsync(at url: URL, id: String? = nil) async throws -> GroundingSource {
    let task = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let source = try Self.importFile(at: url, id: id)
      try Task.checkCancellation()
      return source
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}

nonisolated public struct GroundingProvenance: Codable, Hashable, Sendable {
  public let sourceID: String
  public let sourceName: String
  public let page: Int?
  public let ordinal: Int
  public let characterRange: Range<Int>?
  public init(
    sourceID: String, sourceName: String, page: Int? = nil, ordinal: Int,
    characterRange: Range<Int>? = nil
  ) {
    self.sourceID = sourceID
    self.sourceName = sourceName
    self.page = page
    self.ordinal = ordinal
    self.characterRange = characterRange
  }
  public func validate() throws {
    guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ordinal >= 0,
      page.map({ $0 > 0 }) ?? true,
      characterRange.map({ $0.lowerBound >= 0 && $0.upperBound >= $0.lowerBound }) ?? true
    else { throw GroundingError.invalid("Provenance is invalid") }
  }
}

nonisolated public struct GroundingChunk: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let sourceVersion: Int
  public let text: String
  public let provenance: GroundingProvenance
  public init(id: String, sourceVersion: Int, text: String, provenance: GroundingProvenance) {
    self.id = id
    self.sourceVersion = sourceVersion
    self.text = text
    self.provenance = provenance
  }
  public func validate() throws {
    guard id.count == 64, id.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }),
      sourceVersion == GroundingSource.currentVersion,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw GroundingError.invalid("Chunk is invalid") }
    try provenance.validate()
    if let range = provenance.characterRange, range.count != text.count {
      throw GroundingError.invalid("Chunk range does not match text")
    }
  }
}

nonisolated public struct GroundingChunker: Sendable {
  public let size: Int
  public let overlap: Int
  public init(size: Int = 800, overlap: Int = 120) throws {
    guard size > 0, overlap >= 0, overlap < size else {
      throw GroundingError.invalid("Chunk size and overlap are invalid")
    }
    self.size = size
    self.overlap = overlap
  }
  public func chunks(from source: GroundingSource) -> [GroundingChunk] {
    let chars = Array(source.text)
    guard !chars.isEmpty else { return [] }
    var result: [GroundingChunk] = []
    var start = 0
    var ordinal = 0
    while start < chars.count {
      let hardEnd = min(chars.count, start + size)
      let boundary = chars[start..<hardEnd].lastIndex(where: { $0 == "\n" || $0 == "\r" })
      let end = boundary.map { $0 + 1 >= start + max(1, size / 2) ? $0 + 1 : hardEnd } ?? hardEnd
      let text = String(chars[start..<end])
      let digest = GroundingHash.digest(
        source.id + "\u{1F}" + String(source.version) + "\u{1F}" + String(start) + "\u{1F}" + text)
      result.append(
        GroundingChunk(
          id: digest, sourceVersion: source.version, text: text,
          provenance: GroundingProvenance(
            sourceID: source.id, sourceName: source.name, ordinal: ordinal,
            characterRange: start..<end)))
      ordinal += 1
      if end == chars.count { break }
      start = end - overlap
    }
    return result
  }

  /// Markdown is intentionally treated as text in this foundation layer; preserving
  /// source whitespace is safer than pretending to extract PDF structure here.
  public func chunks(markdown source: GroundingSource) -> [GroundingChunk] { chunks(from: source) }
}

nonisolated public struct GroundingEmbedding: Codable, Hashable, Sendable {
  public let values: [Double]
  public init(_ values: [Double]) throws {
    guard !values.isEmpty, values.allSatisfy({ $0.isFinite }), values.contains(where: { $0 != 0 })
    else {
      throw GroundingError.invalid("Embedding values must be finite and nonempty")
    }
    self.values = values
  }
  public var dimension: Int { values.count }
  public func validate() throws { _ = try GroundingEmbedding(values) }
}

nonisolated public struct GroundingIndexEntry: Codable, Hashable, Sendable, Identifiable {
  public let chunk: GroundingChunk
  public let embedding: GroundingEmbedding
  public var id: String { chunk.id }
  public init(chunk: GroundingChunk, embedding: GroundingEmbedding) throws {
    try chunk.validate()
    try embedding.validate()
    self.chunk = chunk
    self.embedding = embedding
  }
}

nonisolated public struct GroundingIndex: Codable, Hashable, Sendable {
  public static let currentVersion = 1
  public let version: Int
  public let embeddingModel: String
  public let dimension: Int
  public let entries: [GroundingIndexEntry]

  public init(
    version: Int = GroundingIndex.currentVersion, embeddingModel: String, dimension: Int,
    entries: [GroundingIndexEntry] = []
  ) throws {
    self.version = version
    self.embeddingModel = embeddingModel
    self.dimension = dimension
    self.entries = entries
    try validate()
  }

  public func validate() throws {
    guard version == Self.currentVersion,
      !embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      dimension > 0
    else { throw version == Self.currentVersion ? GroundingError.invalid("Index identity is invalid") : .unsupportedVersion }
    guard Set(entries.map(\.id)).count == entries.count else { throw GroundingError.duplicateID }
    for entry in entries {
      try entry.chunk.validate()
      try entry.embedding.validate()
      guard entry.embedding.dimension == dimension else { throw GroundingError.dimensionMismatch }
    }
  }
}

nonisolated public struct GroundingIndexIdentity: Codable, Hashable, Sendable {
  public let embeddingModel: String
  public let dimension: Int

  public init(embeddingModel: String, dimension: Int) {
    self.embeddingModel = embeddingModel
    self.dimension = dimension
  }
}

nonisolated public struct GroundingSourceSummary: Codable, Hashable, Sendable, Identifiable {
  public let sourceID: String
  public let sourceName: String
  public let sourceVersion: Int
  public let chunkCount: Int
  public var id: String { sourceID }

  public init(sourceID: String, sourceName: String, sourceVersion: Int, chunkCount: Int) {
    self.sourceID = sourceID
    self.sourceName = sourceName
    self.sourceVersion = sourceVersion
    self.chunkCount = chunkCount
  }
}

nonisolated enum GroundingHash {
  static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
