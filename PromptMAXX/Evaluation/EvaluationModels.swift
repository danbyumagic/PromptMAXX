import Foundation

nonisolated public struct EvalCase: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public var version: Int
  public var name: String
  public var input: String
  public var checks: [EvalCheck]
  public init(id: String, version: Int = 1, name: String, input: String, checks: [EvalCheck]) {
    self.id = id
    self.version = version
    self.name = name
    self.input = input
    self.checks = checks
  }
}

nonisolated public struct EvalSuite: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public var version: Int
  public var name: String
  public var description: String
  public var cases: [EvalCase]
  public init(
    id: String, version: Int = 1, name: String, description: String = "", cases: [EvalCase]
  ) {
    self.id = id
    self.version = version
    self.name = name
    self.description = description
    self.cases = cases
  }
  public func validate() throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EvaluationConfigurationError.invalid("Suite ID is required")
    }
    guard version > 0 else {
      throw EvaluationConfigurationError.invalid("Suite version must be positive")
    }
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EvaluationConfigurationError.invalid("Suite name is required")
    }
    guard !cases.isEmpty else {
      throw EvaluationConfigurationError.invalid("Suite must contain at least one case")
    }
    let ids = cases.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard ids.allSatisfy({ !$0.isEmpty }) else {
      throw EvaluationConfigurationError.invalid("Case IDs are required")
    }
    guard Set(ids).count == ids.count else {
      throw EvaluationConfigurationError.invalid("Case IDs must be unique")
    }
    for evalCase in cases {
      guard !evalCase.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !evalCase.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !evalCase.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !evalCase.checks.isEmpty
      else {
        throw EvaluationConfigurationError.invalid("Cases require ID, name, input, and checks")
      }
      guard evalCase.version > 0 else {
        throw EvaluationConfigurationError.invalid("Case versions must be positive")
      }
      let checkIDs = evalCase.checks.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard checkIDs.allSatisfy({ !$0.isEmpty }), Set(checkIDs).count == checkIDs.count else {
        throw EvaluationConfigurationError.invalid("Check IDs must be non-empty and unique")
      }
      for check in evalCase.checks {
        if [.requiredJSONPath, .contains, .regex].contains(check.kind),
          check.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          throw EvaluationConfigurationError.invalid("Check values are required")
        }
        if check.kind == .equalsJSONPath {
          guard !check.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            check.expected != nil
          else {
            throw EvaluationConfigurationError.invalid(
              "Exact JSON path checks require a path and expected value")
          }
        }
        if check.kind == .regex, (try? NSRegularExpression(pattern: check.value)) == nil {
          throw EvaluationConfigurationError.invalid("Invalid regular expression")
        }
      }
    }
  }
}

nonisolated public enum EvalCheckKind: String, Codable, Hashable, Sendable {
  case nonEmpty, validJSON, requiredJSONPath, equalsJSONPath, contains, regex
}
nonisolated public enum EvalExpectedValue: Codable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
}
nonisolated public struct EvalCheck: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public var kind: EvalCheckKind
  public var value: String
  public var label: String
  public var expected: EvalExpectedValue?
  public init(
    id: String, kind: EvalCheckKind, value: String = "", label: String = "",
    expected: EvalExpectedValue? = nil
  ) {
    self.id = id
    self.kind = kind
    self.value = value
    self.label = label
    self.expected = expected
  }
  public func evaluate(_ output: String) -> EvalCheckResult {
    let passed: Bool
    var failureDetail = "Did not match"
    let display = label.isEmpty ? kind.rawValue : label
    switch kind {
    case .nonEmpty: passed = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .validJSON: passed = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) != nil
    case .requiredJSONPath: passed = Self.value(at: value, in: output) != nil
    case .equalsJSONPath:
      guard let actual = Self.value(at: value, in: output), let expected else {
        return EvalCheckResult(
          checkID: id, label: display, passed: false,
          detail: expected == nil ? "Expected value is missing" : "JSON path is missing")
      }
      passed = Self.matches(actual, expected)
      if !passed {
        let expectedText = Self.render(expected)
        let actualText = Self.render(actual) ?? "non-scalar value (wrong type)"
        failureDetail = "JSON path '\(value)' expected \(expectedText), got \(actualText)"
      }
    case .contains: passed = output.localizedCaseInsensitiveContains(value)
    case .regex:
      guard let regex = try? NSRegularExpression(pattern: value) else {
        return EvalCheckResult(
          checkID: id, label: display, passed: false, detail: "Invalid regular expression")
      }
      passed =
        regex.firstMatch(
          in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)) != nil
    }
    return EvalCheckResult(
      checkID: id, label: display, passed: passed,
      detail: passed
        ? "Passed"
        : failureDetail)
  }
  private static func matches(_ value: Any, _ expected: EvalExpectedValue) -> Bool {
    switch expected {
    case .string(let expected): return (value as? String) == expected
    case .bool(let expected): return (value as? Bool) == expected
    case .null: return value is NSNull
    case .number(let expected):
      guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
        return false
      }
      return number.doubleValue == expected
    }
  }
  private static func render(_ expected: EvalExpectedValue) -> String {
    switch expected {
    case .string(let value): return "string \"\(value)\""
    case .number(let value): return "number \(value)"
    case .bool(let value): return "bool \(value)"
    case .null: return "null"
    }
  }
  private static func render(_ value: Any) -> String? {
    if value is NSNull { return "null" }
    if let value = value as? String { return "string \"\(value)\"" }
    if let value = value as? Bool { return "bool \(value)" }
    if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
      return "number \(value.doubleValue)"
    }
    return nil
  }
  private static func value(at path: String, in output: String) -> Any? {
    guard let root = try? JSONSerialization.jsonObject(with: Data(output.utf8)) else { return nil }
    return path.split(separator: ".").reduce(root) { current, component in
      guard let current else { return nil }
      if let dict = current as? [String: Any] { return dict[String(component)] }
      if let array = current as? [Any], let i = Int(component), array.indices.contains(i) {
        return array[i]
      }
      return nil
    }
  }
}
nonisolated public struct EvalCheckResult: Codable, Hashable, Sendable {
  public let checkID: String
  public let label: String
  public let passed: Bool
  public let detail: String
  public init(checkID: String, label: String, passed: Bool, detail: String) {
    self.checkID = checkID
    self.label = label
    self.passed = passed
    self.detail = detail
  }
}

nonisolated public struct EvalCandidateConfiguration: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public var version: Int
  public var label: String
  public var model: String
  public var instruction: String
  public var generationOptions: PromptGenerationOptions
  public var format: OllamaResponseFormat?
  public init(
    id: String, version: Int = 1, label: String, model: String, instruction: String,
    generationOptions: PromptGenerationOptions = .init(), format: OllamaResponseFormat? = nil
  ) {
    self.id = id
    self.version = version
    self.label = label
    self.model = model
    self.instruction = instruction
    self.generationOptions = generationOptions
    self.format = format
  }
  public func validate() throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EvaluationConfigurationError.invalid("Candidate ID is required")
    }
    guard version > 0 else {
      throw EvaluationConfigurationError.invalid("Candidate version must be positive")
    }
    guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EvaluationConfigurationError.invalid("Candidate label is required")
    }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EvaluationConfigurationError.invalid("Candidate model is required")
    }
    guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EvaluationConfigurationError.invalid("Candidate instruction is required")
    }
    guard generationOptions.isValid else {
      throw EvaluationConfigurationError.invalid("Candidate generation options are invalid")
    }
  }
}

nonisolated public struct EvalCaseResult: Codable, Hashable, Sendable, Identifiable {
  public let caseID: String
  public let suiteCaseVersion: Int
  public let candidateID: String
  public let candidateLabel: String
  public let candidateVersion: Int
  public let model: String
  public let output: String?
  public let error: String?
  public let checkResults: [EvalCheckResult]
  public let latencyMilliseconds: Double?
  public let inputTokenCount: Int?
  public let outputTokenCount: Int?
  public let startedAt: Date?
  public let finishedAt: Date?
  public var id: String { "\(candidateID)::\(caseID)" }
  public var passed: Bool {
    error == nil && !checkResults.isEmpty && checkResults.allSatisfy(\.passed)
  }
  public var checksPassed: Int { checkResults.filter(\.passed).count }
  public init(
    caseID: String, suiteCaseVersion: Int, candidateID: String, candidateLabel: String,
    candidateVersion: Int, model: String, output: String?, error: String?,
    checkResults: [EvalCheckResult], latencyMilliseconds: Double?, inputTokenCount: Int?,
    outputTokenCount: Int?, startedAt: Date? = nil, finishedAt: Date? = nil
  ) {
    self.caseID = caseID
    self.suiteCaseVersion = suiteCaseVersion
    self.candidateID = candidateID
    self.candidateLabel = candidateLabel
    self.candidateVersion = candidateVersion
    self.model = model
    self.output = output
    self.error = error
    self.checkResults = checkResults
    self.latencyMilliseconds = latencyMilliseconds
    self.inputTokenCount = inputTokenCount
    self.outputTokenCount = outputTokenCount
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}
nonisolated public struct EvalCandidateSummary: Codable, Hashable, Sendable {
  public let candidateID: String
  public let candidateLabel: String
  public let candidateVersion: Int
  public let model: String
  public let totalCases: Int
  public let passedCases: Int
  public let averageLatencyMilliseconds: Double?
  public let averageInputTokens: Double?
  public let averageOutputTokens: Double?
  public var passRate: Double { totalCases == 0 ? 0 : Double(passedCases) / Double(totalCases) }
}
nonisolated public struct EvalReport: Codable, Hashable, Sendable {
  public let suite: EvalSuite
  public let candidates: [EvalCandidateConfiguration]
  public let startedAt: Date
  public let finishedAt: Date
  public var suiteID: String { suite.id }
  public var suiteVersion: Int { suite.version }
  public let results: [EvalCaseResult]
  public var totalCases: Int { results.count }
  public var passedCases: Int { results.filter(\.passed).count }
  public var passRate: Double { totalCases == 0 ? 0 : Double(passedCases) / Double(totalCases) }
  public var summaries: [EvalCandidateSummary] {
    candidates.compactMap { candidate in
      let group = results.filter { $0.candidateID == candidate.id }
      guard let first = group.first else { return nil }
      let avg: ([Double]) -> Double? = { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
      return EvalCandidateSummary(
        candidateID: first.candidateID, candidateLabel: first.candidateLabel,
        candidateVersion: first.candidateVersion, model: first.model, totalCases: group.count,
        passedCases: group.filter(\.passed).count,
        averageLatencyMilliseconds: avg(group.compactMap(\.latencyMilliseconds)),
        averageInputTokens: avg(group.compactMap { $0.inputTokenCount.map(Double.init) }),
        averageOutputTokens: avg(group.compactMap { $0.outputTokenCount.map(Double.init) }))
    }
  }
  public init(
    suite: EvalSuite, candidates: [EvalCandidateConfiguration], startedAt: Date, finishedAt: Date,
    results: [EvalCaseResult]
  ) {
    self.suite = suite
    self.candidates = candidates
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.results = results
  }
  public func markdown() -> String {
    var lines = ["# Evaluation: \(suiteID)", ""]
    for s in summaries {
      lines.append(
        "- \(s.candidateLabel) (\(s.candidateID) v\(s.candidateVersion)): \(String(format:"%.1f%%",s.passRate*100)) (\(s.passedCases)/\(s.totalCases))"
      )
    }
    lines += ["", "| Case | Candidate | Result | Checks |", "| --- | --- | --- | ---: |"]
    for r in results {
      lines.append(
        "| \(r.id) | \(r.candidateLabel) | \(r.passed ? "PASS":"FAIL") | \(r.checksPassed)/\(r.checkResults.count) |"
      )
    }
    return lines.joined(separator: "\n") + "\n"
  }
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }
}
nonisolated public enum EvaluationConfigurationError: Error, LocalizedError, Hashable, Sendable {
  case invalid(String)
  public var errorDescription: String? {
    if case .invalid(let s) = self { return s }
    return nil
  }
}
