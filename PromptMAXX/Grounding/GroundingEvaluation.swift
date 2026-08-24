import Foundation

nonisolated public struct GroundingRecallCase: Codable, Hashable, Sendable {
  public let relevantSourceIDs: Set<String>
  public let query: String
  public init(query: String, relevantSourceIDs: Set<String>) throws {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !relevantSourceIDs.isEmpty,
      relevantSourceIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else { throw GroundingError.invalid("Recall case is invalid") }
    self.query = query
    self.relevantSourceIDs = relevantSourceIDs
  }
}

nonisolated public struct GroundingRecallReport: Codable, Hashable, Sendable {
  public let total: Int
  public let k: Int
  public let hits: Int
  public let hitRateAtK: Double
  public let recallAtK: Double
  public let sourceCoverage: Double
  public init(
    total: Int, k: Int, hits: Int, hitRateAtK: Double, recallAtK: Double, sourceCoverage: Double
  ) {
    self.total = total
    self.hitRateAtK = hitRateAtK
    self.k = k
    self.hits = hits
    self.recallAtK = recallAtK
    self.sourceCoverage = sourceCoverage
  }
}

nonisolated public enum GroundingEvaluation {
  public static func evaluate(cases: [GroundingRecallCase], retrieved: [[GroundingMatch]], k: Int)
    throws -> GroundingRecallReport
  {
    guard k > 0, cases.count == retrieved.count else {
      throw GroundingError.invalid("Recall inputs do not match")
    }
    guard !cases.isEmpty else {
      return .init(
        total: 0, k: k, hits: 0, hitRateAtK: 0, recallAtK: 0, sourceCoverage: 0,
      )
    }
    let rows = zip(cases, retrieved).map { ($0, Array($1.prefix(k))) }
    let hitFlags = rows.map {
      !$0.0.relevantSourceIDs.isDisjoint(with: Set($0.1.map { $0.chunk.provenance.sourceID }))
    }
    let hitRate = Double(hitFlags.filter { $0 }.count) / Double(cases.count)
    let recall =
      rows.map { pair in
        Double(
          pair.0.relevantSourceIDs.intersection(pair.1.map { $0.chunk.provenance.sourceID }).count)
          / Double(pair.0.relevantSourceIDs.count)
      }.reduce(0, +) / Double(cases.count)
    let unionRelevant = Set(cases.flatMap { $0.relevantSourceIDs })
    let unionRetrieved = Set(rows.flatMap { $0.1.map { $0.chunk.provenance.sourceID } })
    let sourceCoverage =
      Double(unionRelevant.intersection(unionRetrieved).count) / Double(unionRelevant.count)
    return .init(
      total: cases.count, k: k, hits: hitFlags.filter { $0 }.count, hitRateAtK: hitRate,
      recallAtK: recall, sourceCoverage: sourceCoverage)
  }
}
