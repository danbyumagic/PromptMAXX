import Foundation

/// Actor-isolated persistence for one identity-bound embedding index.
public actor GroundingIndexRepository {
  private let url: URL
  private let fileManager: FileManager

  public init(url: URL, fileManager: FileManager = .default) throws {
    guard url.isFileURL else { throw GroundingError.invalidURL }
    self.url = url
    self.fileManager = fileManager
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      throw GroundingError.directory
    }
  }

  public init(fileManager: FileManager = .default) throws {
    try self.init(url: Self.defaultURL(fileManager: fileManager), fileManager: fileManager)
  }

  public static func defaultURL(
    applicationName: String = "PromptMAXX", fileManager: FileManager = .default
  ) throws -> URL {
    guard !applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { throw GroundingError.invalidURL }
    return base.appendingPathComponent(applicationName, isDirectory: true)
      .appendingPathComponent("grounding-index.json", isDirectory: false)
  }

  public func save(_ index: GroundingIndex) throws {
    try index.validate()
    // Decode/validate the old bytes before any mutation. A corrupt or
    // unsupported store is never silently replaced by a new index.
    if fileManager.fileExists(atPath: url.path) { _ = try loadIndex() }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data: Data
    do {
      data = try encoder.encode(index)
    } catch {
      throw GroundingError.encode(error.localizedDescription)
    }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".grounding-\(UUID().uuidString).tmp")
    defer { try? fileManager.removeItem(at: temporary) }
    do {
      try data.write(to: temporary, options: .atomic)
    } catch {
      throw GroundingError.write(error.localizedDescription)
    }
    do {
      if fileManager.fileExists(atPath: url.path) {
        _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: url)
      }
    } catch {
      throw GroundingError.replace(error.localizedDescription)
    }
  }

  /// Compatibility wrapper for the original entry-only repository API.
  /// New callers should persist a full `GroundingIndex` with a real model ID.
  public func save(_ entries: [GroundingIndexEntry]) throws {
    guard let dimension = entries.first?.embedding.dimension else {
      throw GroundingError.invalidDimension
    }
    try save(try GroundingIndex(embeddingModel: "legacy", dimension: dimension, entries: entries))
  }

  public func loadIndex() throws -> GroundingIndex? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw GroundingError.read(error.localizedDescription)
    }
    let index: GroundingIndex
    do {
      index = try JSONDecoder().decode(GroundingIndex.self, from: data)
    } catch let error as GroundingError {
      throw error
    } catch {
      throw GroundingError.decode(error.localizedDescription)
    }
    do {
      try index.validate()
    } catch let error as GroundingError {
      throw error
    } catch {
      throw GroundingError.invalidEnvelope
    }
    return index
  }

  /// Compatibility wrapper for the original entry-only repository API.
  public func load() throws -> [GroundingIndexEntry] {
    try loadIndex()?.entries ?? []
  }

  public func clear() throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    _ = try loadIndex()
    try removeIndexFile()
  }

  /// Destructive reset for an explicitly confirmed user action. Unlike
  /// `clear`, this intentionally removes corrupt/unsupported bytes so a store
  /// can recover without silently hiding data loss.
  public func discard() throws {
    try removeIndexFile()
  }

  private func removeIndexFile() throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    do {
      try fileManager.removeItem(at: url)
    } catch {
      throw GroundingError.write(error.localizedDescription)
    }
  }
}
