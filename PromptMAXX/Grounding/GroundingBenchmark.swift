import Foundation

/// The split used by a benchmark query. `all` is a run selection and is not
/// valid on an individual query.
nonisolated public enum GroundingBenchmarkSplit: String, Codable, CaseIterable, Hashable, Sendable {
  case tuning
  case heldOut = "held-out"
  case all

  public var displayName: String {
    switch self {
    case .tuning: return "Tuning"
    case .heldOut: return "Held-out"
    case .all: return "All"
    }
  }
}

nonisolated public enum GroundingBenchmarkEndpointLocality: String, Codable, CaseIterable, Hashable, Sendable {
  case local
  case remote
  case unavailable

  public var displayName: String {
    switch self {
    case .local: return "Local"
    case .remote: return "Remote"
    case .unavailable: return "Unavailable"
    }
  }
}

nonisolated public enum GroundingBenchmarkError: Error, LocalizedError, Codable, Hashable, Sendable {
  case invalidConfiguration(String)
  case invalidSuite(String)
  case invalidProviderResponse(String)
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message): return "Benchmark configuration is invalid: \(message)"
    case .invalidSuite(let message): return "Benchmark suite is invalid: \(message)"
    case .invalidProviderResponse(let message):
      return "The embedding provider returned an invalid benchmark response: \(message)"
    case .cancelled: return "The benchmark was cancelled."
    }
  }
}

/// A stable, redistributable query definition. IDs and source IDs are plain
/// deterministic strings rather than runtime UUIDs, so a report can be
/// reproduced across machines and app launches.
nonisolated public struct GroundingBenchmarkQuery: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let query: String
  public let relevantSourceIDs: [String]
  public let split: GroundingBenchmarkSplit

  public init(
    id: String,
    query: String,
    relevantSourceIDs: [String],
    split: GroundingBenchmarkSplit
  ) throws {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceIDs = Array(
      Set(relevantSourceIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        .filter { !$0.isEmpty }
    ).sorted()
    guard !normalizedID.isEmpty, !normalizedQuery.isEmpty, !sourceIDs.isEmpty,
      split != .all
    else { throw GroundingBenchmarkError.invalidSuite("Query fields are invalid") }
    self.id = normalizedID
    self.query = normalizedQuery
    self.relevantSourceIDs = sourceIDs
    self.split = split
  }

  public init(
    id: String,
    query: String,
    relevantSourceIDs: Set<String>,
    split: GroundingBenchmarkSplit
  ) throws {
    try self.init(
      id: id, query: query, relevantSourceIDs: Array(relevantSourceIDs), split: split)
  }
}

/// The corpus is intentionally text-only and authored in source, so the demo
/// can be redistributed with the app without downloading or licensing a
/// hidden data file. Source IDs are stable slugs and are part of the suite's
/// public contract.
nonisolated public struct GroundingBenchmarkCorpus: Codable, Hashable, Sendable {
  public static let currentVersion = 1
  public let id: String
  public let version: Int
  public let sources: [GroundingSource]

  public init(id: String, version: Int = currentVersion, sources: [GroundingSource]) throws {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedID.isEmpty, version == Self.currentVersion, !sources.isEmpty else {
      throw GroundingBenchmarkError.invalidSuite("Corpus identity or sources are invalid")
    }
    guard Set(sources.map(\.id)).count == sources.count else {
      throw GroundingBenchmarkError.invalidSuite("Corpus source IDs must be unique")
    }
    for source in sources { try source.validate() }
    self.id = normalizedID
    self.version = version
    self.sources = sources
  }

  public func validate() throws {
    _ = try Self(id: id, version: version, sources: sources)
  }
}

nonisolated public struct GroundingBenchmarkSuite: Codable, Hashable, Sendable {
  public static let currentVersion = 1
  public let id: String
  public let version: Int
  public let name: String
  public let corpus: GroundingBenchmarkCorpus
  public let queries: [GroundingBenchmarkQuery]

  public init(
    id: String,
    version: Int = currentVersion,
    name: String,
    corpus: GroundingBenchmarkCorpus,
    queries: [GroundingBenchmarkQuery]
  ) throws {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedID.isEmpty, !normalizedName.isEmpty,
      version == Self.currentVersion, !queries.isEmpty
    else { throw GroundingBenchmarkError.invalidSuite("Suite identity or queries are invalid") }
    try corpus.validate()
    guard Set(queries.map(\.id)).count == queries.count else {
      throw GroundingBenchmarkError.invalidSuite("Query IDs must be unique")
    }
    let sourceIDs = Set(corpus.sources.map(\.id))
    guard queries.allSatisfy({
      $0.split != .all && Set($0.relevantSourceIDs).isSubset(of: sourceIDs)
    }) else {
      throw GroundingBenchmarkError.invalidSuite("Queries reference unknown sources")
    }
    self.id = normalizedID
    self.version = version
    self.name = normalizedName
    self.corpus = corpus
    self.queries = queries
  }

  public func validate() throws {
    for query in queries {
      _ = try GroundingBenchmarkQuery(
        id: query.id,
        query: query.query,
        relevantSourceIDs: query.relevantSourceIDs,
        split: query.split)
    }
    _ = try Self(
      id: id, version: version, name: name, corpus: corpus, queries: queries)
  }

  public func queries(for split: GroundingBenchmarkSplit) -> [GroundingBenchmarkQuery] {
    switch split {
    case .all: return queries
    case .tuning, .heldOut: return queries.filter { $0.split == split }
    }
  }

  public var tuningCount: Int { queries.filter { $0.split == .tuning }.count }
  public var heldOutCount: Int { queries.filter { $0.split == .heldOut }.count }

  /// Builds twenty small, original queries over eight stable text sources.
  /// The first ten queries are tuning cases; the final ten are held-out cases.
  /// Three sources are distractors without dedicated queries so a broad
  /// retrieval configuration cannot accidentally report a corpus-wide hit.
  /// The content contains no product secrets or network-dependent facts.
  public static func makeDemo() throws -> GroundingBenchmarkSuite {
    let sourceDefinitions: [(String, String, String)] = [
      (
        "demo-water-quality",
        "Riverbend Water Watch",
        "Riverbend Water Watch publishes a monthly water-quality bulletin. Volunteers collect samples at three bridges on the first Saturday. The lab flags nitrate readings above 10 milligrams per liter for follow-up. The monitoring team stores source measurements in an open CSV archive."
      ),
      (
        "demo-community-garden",
        "Greenfield Community Garden",
        "Greenfield Community Garden assigns plots through a spring lottery. Gardeners may water before 9 a.m. or after 6 p.m. to reduce evaporation. The coordinator reserves ten percent of plots for accessible beds. Compost is turned on the first Sunday of each month."
      ),
      (
        "demo-release-playbook",
        "Northstar Release Playbook",
        "Northstar Release Playbook requires a peer review and a green build before rollout. A release captain owns the change window. Rollback is approved by the incident lead when a health check fails twice. The team freezes production changes during the Friday maintenance window."
      ),
      (
        "demo-privacy-retention",
        "PromptMAXX Privacy Note",
        "PromptMAXX Privacy Note says local endpoints keep prompts on the Mac unless a user configures a remote host. Run traces contain provider responses and are stored in the app support library. Users may export or delete their library documents. A retention review is scheduled every 90 days."
      ),
      (
        "demo-library-access",
        "Harbor Library Access Guide",
        "Harbor Library Access Guide says a new card requires a photo ID and proof of address. Members can reserve two study rooms for up to two hours. Weekend hours are 10 a.m. to 4 p.m. The reference desk maintains a printed accessibility map."
      ),
      (
        "demo-transit-safety",
        "Cedar Transit Safety Note",
        "Cedar Transit Safety Note recommends reflective clothing after sunset. Operators report blocked bicycle lanes to dispatch. The evening shuttle uses a three-minute dwell time at the market stop."
      ),
      (
        "demo-energy-audit",
        "Maple Energy Audit",
        "Maple Energy Audit records a building's annual electricity use and peak demand. The facilities team checks insulation before replacing equipment."
      ),
      (
        "demo-emergency-plan",
        "Pine Emergency Plan",
        "Pine Emergency Plan assigns an assembly point beside the north gate. Wardens check attendance before re-entry. The plan is reviewed after every drill."
      ),
    ]
    var sources: [GroundingSource] = []
    sources.reserveCapacity(sourceDefinitions.count)
    for (id, name, text) in sourceDefinitions {
      sources.append(try GroundingSource.text(name: name, text: text, id: id))
    }
    let queryDefinitions: [(String, String, [String], GroundingBenchmarkSplit)] = [
      ("q-tuning-01", "How often are Riverbend water samples collected?", ["demo-water-quality"], .tuning),
      ("q-tuning-02", "Which nitrate reading triggers follow-up?", ["demo-water-quality"], .tuning),
      ("q-tuning-03", "How are Greenfield garden plots assigned?", ["demo-community-garden"], .tuning),
      ("q-tuning-04", "When may gardeners water to reduce evaporation?", ["demo-community-garden"], .tuning),
      ("q-tuning-05", "What must happen before a Northstar rollout?", ["demo-release-playbook"], .tuning),
      ("q-tuning-06", "Who owns the release change window?", ["demo-release-playbook"], .tuning),
      ("q-tuning-07", "When do local endpoints keep prompts on the Mac?", ["demo-privacy-retention"], .tuning),
      ("q-tuning-08", "How often is the retention review scheduled?", ["demo-privacy-retention"], .tuning),
      ("q-tuning-09", "What identification is needed for a Harbor library card?", ["demo-library-access"], .tuning),
      ("q-tuning-10", "How many study rooms can a member reserve?", ["demo-library-access"], .tuning),
      ("q-heldout-01", "Where does the monitoring team store measurements?", ["demo-water-quality"], .heldOut),
      ("q-heldout-02", "What happens when a nitrate result is high?", ["demo-water-quality"], .heldOut),
      ("q-heldout-03", "How many garden plots are reserved for accessible beds?", ["demo-community-garden"], .heldOut),
      ("q-heldout-04", "When is garden compost turned?", ["demo-community-garden"], .heldOut),
      ("q-heldout-05", "Who can approve a release rollback?", ["demo-release-playbook"], .heldOut),
      ("q-heldout-06", "When are production changes frozen?", ["demo-release-playbook"], .heldOut),
      ("q-heldout-07", "Where are run traces stored?", ["demo-privacy-retention"], .heldOut),
      ("q-heldout-08", "Which controls are described for PromptMAXX records, and what may Harbor members reserve?", ["demo-privacy-retention", "demo-library-access"], .heldOut),
      ("q-heldout-09", "What are Harbor Library weekend hours?", ["demo-library-access"], .heldOut),
      ("q-heldout-10", "Which access guides mention rooms and accessible beds?", ["demo-library-access", "demo-community-garden"], .heldOut),
    ]
    let corpus = try GroundingBenchmarkCorpus(
      id: "promptmaxx-grounding-demo", sources: sources)
    var queries: [GroundingBenchmarkQuery] = []
    queries.reserveCapacity(queryDefinitions.count)
    for (id, query, sourceIDs, split) in queryDefinitions {
      queries.append(try GroundingBenchmarkQuery(
        id: id, query: query, relevantSourceIDs: sourceIDs, split: split))
    }
    return try GroundingBenchmarkSuite(
      id: "promptmaxx-grounding-demo-suite", name: "PromptMAXX Grounding Demo", corpus: corpus,
      queries: queries)
  }

  public static func builtInDemo() throws -> GroundingBenchmarkSuite {
    try makeDemo()
  }
}

nonisolated public struct GroundingBenchmarkConfiguration: Codable, Hashable, Sendable {
  public let embeddingModel: String
  public let dimensions: Int?
  public let chunkSize: Int
  public let overlap: Int
  public let lexicalWeight: Double
  public let mmrLambda: Double
  public let sameSourcePenalty: Double
  public let topK: Int
  public let characterBudget: Int
  public let split: GroundingBenchmarkSplit
  public let endpointLocality: GroundingBenchmarkEndpointLocality
  public let providerModelVersion: String?

  public init(
    embeddingModel: String,
    dimensions: Int? = nil,
    chunkSize: Int = 800,
    overlap: Int = 120,
    lexicalWeight: Double = 0.15,
    mmrLambda: Double = 0.75,
    sameSourcePenalty: Double = 0.1,
    topK: Int = 3,
    characterBudget: Int = 2_000,
    split: GroundingBenchmarkSplit = .heldOut,
    endpointLocality: GroundingBenchmarkEndpointLocality = .unavailable,
    providerModelVersion: String? = nil
  ) throws {
    let normalizedModel = embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedModel.isEmpty, dimensions.map({ $0 > 0 }) ?? true,
      chunkSize > 0, overlap >= 0, overlap < chunkSize,
      topK > 0, characterBudget > 0,
      lexicalWeight.isFinite, (0...1).contains(lexicalWeight),
      mmrLambda.isFinite, (0...1).contains(mmrLambda),
      sameSourcePenalty.isFinite, sameSourcePenalty >= 0
    else { throw GroundingBenchmarkError.invalidConfiguration("One or more limits or weights are invalid") }
    self.embeddingModel = normalizedModel
    self.dimensions = dimensions
    self.chunkSize = chunkSize
    self.overlap = overlap
    self.lexicalWeight = lexicalWeight
    self.mmrLambda = mmrLambda
    self.sameSourcePenalty = sameSourcePenalty
    self.topK = topK
    self.characterBudget = characterBudget
    self.split = split
    self.endpointLocality = endpointLocality
    let normalizedProviderVersion = providerModelVersion?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.providerModelVersion = normalizedProviderVersion?.isEmpty == false
      ? normalizedProviderVersion
      : nil
  }

  public func validate() throws {
    _ = try Self(
      embeddingModel: embeddingModel,
      dimensions: dimensions,
      chunkSize: chunkSize,
      overlap: overlap,
      lexicalWeight: lexicalWeight,
      mmrLambda: mmrLambda,
      sameSourcePenalty: sameSourcePenalty,
      topK: topK,
      characterBudget: characterBudget,
      split: split,
      endpointLocality: endpointLocality,
      providerModelVersion: providerModelVersion)
  }
}

nonisolated public struct GroundingBenchmarkRunMetadata: Codable, Hashable, Sendable {
  public let suiteID: String
  public let suiteVersion: Int
  public let corpusID: String
  public let corpusVersion: Int
  public let split: GroundingBenchmarkSplit
  public let embeddingModel: String
  public let dimensions: Int?
  public let chunkSize: Int
  public let overlap: Int
  public let lexicalWeight: Double
  public let mmrLambda: Double
  public let sameSourcePenalty: Double
  public let topK: Int
  public let characterBudget: Int
  public let endpointLocality: GroundingBenchmarkEndpointLocality
  public let providerModelVersion: String?
  public let timestamp: Date
  public let completedAt: Date?

  public init(
    suiteID: String,
    suiteVersion: Int,
    corpusID: String,
    corpusVersion: Int,
    split: GroundingBenchmarkSplit,
    embeddingModel: String,
    dimensions: Int?,
    chunkSize: Int,
    overlap: Int,
    lexicalWeight: Double,
    mmrLambda: Double,
    sameSourcePenalty: Double,
    topK: Int,
    characterBudget: Int,
    endpointLocality: GroundingBenchmarkEndpointLocality,
    providerModelVersion: String?,
    timestamp: Date,
    completedAt: Date?
  ) {
    self.suiteID = suiteID
    self.suiteVersion = suiteVersion
    self.corpusID = corpusID
    self.corpusVersion = corpusVersion
    self.split = split
    self.embeddingModel = embeddingModel
    self.dimensions = dimensions
    self.chunkSize = chunkSize
    self.overlap = overlap
    self.lexicalWeight = lexicalWeight
    self.mmrLambda = mmrLambda
    self.sameSourcePenalty = sameSourcePenalty
    self.topK = topK
    self.characterBudget = characterBudget
    self.endpointLocality = endpointLocality
    self.providerModelVersion = providerModelVersion
    self.timestamp = timestamp
    self.completedAt = completedAt
  }
}

nonisolated public enum GroundingBenchmarkCaseStatus: String, Codable, Hashable, Sendable {
  case evaluated
  case zeroResult = "zero-result"
  case error
}

nonisolated public struct GroundingBenchmarkCaseOutcome: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let query: String
  public let split: GroundingBenchmarkSplit
  public let relevantSourceIDs: [String]
  public let retrievedSourceIDs: [String]
  public let retrievedChunkIDs: [String]
  public let hitAtK: Bool
  public let recallAtK: Double
  public let status: GroundingBenchmarkCaseStatus
  public let errorMessage: String?

  public init(
    id: String,
    query: String,
    split: GroundingBenchmarkSplit,
    relevantSourceIDs: [String],
    retrievedSourceIDs: [String],
    retrievedChunkIDs: [String],
    hitAtK: Bool,
    recallAtK: Double,
    status: GroundingBenchmarkCaseStatus,
    errorMessage: String? = nil
  ) {
    self.id = id
    self.query = query
    self.split = split
    self.relevantSourceIDs = relevantSourceIDs
    self.retrievedSourceIDs = retrievedSourceIDs
    self.retrievedChunkIDs = retrievedChunkIDs
    self.hitAtK = hitAtK
    self.recallAtK = recallAtK.isFinite ? min(1, max(0, recallAtK)) : 0
    self.status = status
    self.errorMessage = errorMessage
  }
}

nonisolated public struct GroundingBenchmarkAggregate: Codable, Hashable, Sendable {
  public let totalCases: Int
  public let evaluatedCases: Int
  public let hits: Int
  public let hitRateAtK: Double
  public let recallAtK: Double
  public let sourceCoverage: Double
  public let zeroResultCount: Int
  public let errorCount: Int

  public init(outcomes: [GroundingBenchmarkCaseOutcome]) {
    totalCases = outcomes.count
    let evaluated = outcomes.filter { $0.status != .error }
    evaluatedCases = evaluated.count
    hits = evaluated.filter(\.hitAtK).count
    // Errors remain misses in the aggregate rates. `evaluatedCases` and
    // `errorCount` are retained separately so consumers can see the
    // denominator and diagnose a deceptively small successful subset.
    hitRateAtK = outcomes.isEmpty ? 0 : Double(hits) / Double(outcomes.count)
    recallAtK = outcomes.isEmpty
      ? 0
      : outcomes.map(\.recallAtK).reduce(0, +) / Double(outcomes.count)
    zeroResultCount = outcomes.filter { $0.status == .zeroResult }.count
    errorCount = outcomes.filter { $0.status == .error }.count
    let expected = Set(outcomes.flatMap(\.relevantSourceIDs))
    let retrieved = Set(outcomes.flatMap(\.retrievedSourceIDs))
    sourceCoverage = expected.isEmpty ? 0 : Double(expected.intersection(retrieved).count) / Double(expected.count)
  }
}

nonisolated public struct GroundingBenchmarkReport: Codable, Hashable, Sendable {
  public let metadata: GroundingBenchmarkRunMetadata
  public let outcomes: [GroundingBenchmarkCaseOutcome]
  public let aggregate: GroundingBenchmarkAggregate

  public init(metadata: GroundingBenchmarkRunMetadata, outcomes: [GroundingBenchmarkCaseOutcome]) {
    self.metadata = metadata
    self.outcomes = outcomes
    self.aggregate = GroundingBenchmarkAggregate(outcomes: outcomes)
  }

  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }

  public func markdown() -> String {
    let dateFormatter = ISO8601DateFormatter()
    var lines = [
      "# Grounding benchmark report",
      "",
      "This report measures retrieval against the versioned benchmark queries. It does not measure answer quality.",
      "",
      "## Configuration",
      "",
      "- Suite: \(cell(metadata.suiteID)) v\(metadata.suiteVersion) (\(metadata.split.displayName))",
      "- Corpus: \(cell(metadata.corpusID)) v\(metadata.corpusVersion)",
      "- Embedding model: \(cell(metadata.embeddingModel))",
      "- Endpoint locality: \(metadata.endpointLocality.displayName)",
      "- Provider/model version: \(cell(metadata.providerModelVersion ?? "unavailable"))",
      "- Dimensions: \(metadata.dimensions.map(String.init) ?? "provider-selected")",
      "- Chunking: size \(metadata.chunkSize), overlap \(metadata.overlap)",
      "- Retriever: lexical weight \(format(metadata.lexicalWeight)), MMR lambda \(format(metadata.mmrLambda)), source penalty \(format(metadata.sameSourcePenalty))",
      "- Retrieval limits: k \(metadata.topK), character budget \(metadata.characterBudget)",
      "- Timestamp: \(dateFormatter.string(from: metadata.timestamp))",
      "- Completed: \(metadata.completedAt.map(dateFormatter.string(from:)) ?? "unavailable")",
      "",
      "## Aggregate retrieval metrics",
      "",
      "- Cases: \(aggregate.totalCases); evaluated: \(aggregate.evaluatedCases); errors: \(aggregate.errorCount) (errors count as misses in rates)",
      "- Hit rate @ k: \(formatPercent(aggregate.hitRateAtK))",
      "- Mean recall @ k: \(formatPercent(aggregate.recallAtK))",
      "- Source coverage: \(formatPercent(aggregate.sourceCoverage))",
      "- Zero-result cases: \(aggregate.zeroResultCount)",
      "",
      "## Per-case outcomes",
      "",
      "| Case | Split | Query | Status | Hit @ k | Recall @ k | Expected sources | Retrieved sources | Retrieved chunks | Error |",
      "| --- | --- | --- | --- | ---: | ---: | --- | --- | --- | --- |",
    ]
    for outcome in outcomes {
      let expectedSources = outcome.relevantSourceIDs.isEmpty ? "—" : outcome.relevantSourceIDs.joined(separator: ", ")
      let retrievedSources = outcome.retrievedSourceIDs.isEmpty ? "—" : outcome.retrievedSourceIDs.joined(separator: ", ")
      let retrievedChunks = outcome.retrievedChunkIDs.isEmpty ? "—" : outcome.retrievedChunkIDs.joined(separator: ", ")
      let error = outcome.errorMessage ?? "—"
      lines.append(
        "| \(cell(outcome.id)) | \(outcome.split.displayName) | \(cell(outcome.query)) | \(outcome.status.rawValue) | \(outcome.hitAtK ? "yes" : "no") | \(formatPercent(outcome.recallAtK)) | \(cell(expectedSources)) | \(cell(retrievedSources)) | \(cell(retrievedChunks)) | \(cell(error)) |"
      )
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func format(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private func formatPercent(_ value: Double) -> String {
    String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), value * 100)
  }

  private func cell(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "|", with: "\\|")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
  }
}

nonisolated public struct GroundingBenchmarkProgress: Hashable, Sendable {
  public enum Phase: String, Hashable, Sendable {
    case embeddingCorpus
    case evaluatingQueries
  }

  public let phase: Phase
  public let completed: Int
  public let total: Int
  public let currentQueryID: String?
  public let errorMessage: String?

  public init(
    phase: Phase,
    completed: Int,
    total: Int,
    currentQueryID: String? = nil,
    errorMessage: String? = nil
  ) {
    self.phase = phase
    self.completed = completed
    self.total = total
    self.currentQueryID = currentQueryID
    self.errorMessage = errorMessage
  }
}

/// Runs retrieval in memory using an injected embedding provider. It does
/// not write to the user's grounding index and never contacts a provider
/// unless the caller explicitly starts a run.
public actor GroundingBenchmarkRunner {
  private let embeddingProvider: any EmbeddingProvider
  private let clock: @Sendable () -> Date

  public init(
    embeddingProvider: any EmbeddingProvider,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.embeddingProvider = embeddingProvider
    self.clock = clock
  }

  public func run(
    suite: GroundingBenchmarkSuite,
    configuration: GroundingBenchmarkConfiguration,
    progress: (@Sendable (GroundingBenchmarkProgress) -> Void)? = nil
  ) async throws -> GroundingBenchmarkReport {
    try suite.validate()
    try configuration.validate()
    let selectedQueries = suite.queries(for: configuration.split)
    guard !selectedQueries.isEmpty else {
      throw GroundingBenchmarkError.invalidSuite("The selected split contains no queries")
    }
    let chunker: GroundingChunker
    let retriever: GroundingRetriever
    do {
      chunker = try GroundingChunker(size: configuration.chunkSize, overlap: configuration.overlap)
      retriever = try GroundingRetriever(
        lexicalWeight: configuration.lexicalWeight,
        mmrLambda: configuration.mmrLambda,
        sameSourcePenalty: configuration.sameSourcePenalty)
    } catch {
      throw GroundingBenchmarkError.invalidConfiguration(error.localizedDescription)
    }
    let timestamp = clock()
    let chunks = suite.corpus.sources.flatMap { chunker.chunks(from: $0) }
    guard !chunks.isEmpty else {
      throw GroundingBenchmarkError.invalidSuite("The corpus contains no indexable chunks")
    }
    var entries: [GroundingIndexEntry] = []
    entries.reserveCapacity(chunks.count)
    var resolvedDimensions = configuration.dimensions
    for start in stride(from: 0, to: chunks.count, by: 16) {
      try Task.checkCancellation()
      let end = min(chunks.count, start + 16)
      let batch = Array(chunks[start..<end])
      let response: OllamaEmbedResponse
      do {
        response = try await embeddingProvider.embed(
          model: configuration.embeddingModel,
          inputs: batch.map(\.text),
          dimensions: resolvedDimensions)
        try Task.checkCancellation()
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw GroundingBenchmarkError.invalidProviderResponse(error.localizedDescription)
      }
      try validate(
        response, model: configuration.embeddingModel, count: batch.count,
        dimensions: resolvedDimensions)
      let dimension = response.embeddings[0].count
      resolvedDimensions = dimension
      for (chunk, values) in zip(batch, response.embeddings) {
        entries.append(try GroundingIndexEntry(
          chunk: chunk, embedding: GroundingEmbedding(values)))
      }
      progress?(GroundingBenchmarkProgress(
        phase: .embeddingCorpus, completed: end, total: chunks.count))
    }

    var outcomes: [GroundingBenchmarkCaseOutcome] = []
    outcomes.reserveCapacity(selectedQueries.count)
    for (index, query) in selectedQueries.enumerated() {
      try Task.checkCancellation()
      var outcome: GroundingBenchmarkCaseOutcome
      do {
        let response = try await embeddingProvider.embed(
          model: configuration.embeddingModel,
          input: query.query,
          dimensions: resolvedDimensions)
        try Task.checkCancellation()
        try validate(
          response, model: configuration.embeddingModel, count: 1,
          dimensions: resolvedDimensions)
        let queryEmbedding = try GroundingEmbedding(response.embeddings[0])
        let matches = try retriever.retrieve(
          query: query.query,
          embedding: queryEmbedding,
          entries: entries,
          topK: configuration.topK,
          characterBudget: configuration.characterBudget)
        let retrievedSourceIDs = Array(Set(matches.map { $0.chunk.provenance.sourceID })).sorted()
        let relevant = Set(query.relevantSourceIDs)
        let retrieved = Set(retrievedSourceIDs)
        let intersectionCount = relevant.intersection(retrieved).count
        let hit = intersectionCount > 0
        let recall = Double(intersectionCount) / Double(relevant.count)
        outcome = GroundingBenchmarkCaseOutcome(
          id: query.id,
          query: query.query,
          split: query.split,
          relevantSourceIDs: query.relevantSourceIDs,
          retrievedSourceIDs: retrievedSourceIDs,
          retrievedChunkIDs: matches.map(\.id),
          hitAtK: hit,
          recallAtK: recall,
          status: matches.isEmpty ? .zeroResult : .evaluated)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        if Task.isCancelled { throw CancellationError() }
        outcome = GroundingBenchmarkCaseOutcome(
          id: query.id,
          query: query.query,
          split: query.split,
          relevantSourceIDs: query.relevantSourceIDs,
          retrievedSourceIDs: [],
          retrievedChunkIDs: [],
          hitAtK: false,
          recallAtK: 0,
          status: .error,
          errorMessage: error.localizedDescription)
      }
      outcomes.append(outcome)
      progress?(GroundingBenchmarkProgress(
        phase: .evaluatingQueries,
        completed: index + 1,
        total: selectedQueries.count,
        currentQueryID: query.id,
        errorMessage: outcome.errorMessage))
    }
    try Task.checkCancellation()
    let metadata = GroundingBenchmarkRunMetadata(
      suiteID: suite.id,
      suiteVersion: suite.version,
      corpusID: suite.corpus.id,
      corpusVersion: suite.corpus.version,
      split: configuration.split,
      embeddingModel: configuration.embeddingModel,
      dimensions: resolvedDimensions,
      chunkSize: configuration.chunkSize,
      overlap: configuration.overlap,
      lexicalWeight: configuration.lexicalWeight,
      mmrLambda: configuration.mmrLambda,
      sameSourcePenalty: configuration.sameSourcePenalty,
      topK: configuration.topK,
      characterBudget: configuration.characterBudget,
      endpointLocality: configuration.endpointLocality,
      providerModelVersion: configuration.providerModelVersion,
      timestamp: timestamp,
      completedAt: clock())
    try Task.checkCancellation()
    return GroundingBenchmarkReport(metadata: metadata, outcomes: outcomes)
  }

  public func run(
    configuration: GroundingBenchmarkConfiguration,
    progress: (@Sendable (GroundingBenchmarkProgress) -> Void)? = nil
  ) async throws -> GroundingBenchmarkReport {
    try await run(
      suite: try GroundingBenchmarkSuite.makeDemo(),
      configuration: configuration,
      progress: progress)
  }

  private func validate(
    _ response: OllamaEmbedResponse,
    model: String,
    count: Int,
    dimensions: Int?
  ) throws {
    guard response.model == model, response.embeddings.count == count,
      let dimension = response.embeddings.first?.count, dimension > 0
    else {
      throw GroundingBenchmarkError.invalidProviderResponse("model or embedding count mismatch")
    }
    if let dimensions, dimensions != dimension {
      throw GroundingBenchmarkError.invalidProviderResponse("embedding dimension mismatch")
    }
    guard response.embeddings.allSatisfy({
      $0.count == dimension && $0.allSatisfy(\.isFinite) && $0.contains(where: { $0 != 0 })
    }) else {
      throw GroundingBenchmarkError.invalidProviderResponse("embedding values are invalid")
    }
  }
}
