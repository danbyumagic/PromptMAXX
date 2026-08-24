import Darwin
import Foundation

private struct CLIError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

private struct BenchmarkCLIOptions {
  var host = "127.0.0.1"
  var port = 11_434
  var model = "nomic-embed-text"
  var dimensions: Int?
  var chunkSize = 800
  var overlap = 120
  var lexicalWeight = 0.15
  var mmrLambda = 0.75
  var sameSourcePenalty = 0.1
  var topK = 3
  var characterBudget = 2_000
  var split = GroundingBenchmarkSplit.heldOut
  var outputDirectory = URL(fileURLWithPath: "benchmark-results", isDirectory: true)
  var allowRemote = false

  static func parse(_ arguments: [String]) throws -> BenchmarkCLIOptions {
    var options = BenchmarkCLIOptions()
    var index = 0

    func value(after flag: String) throws -> String {
      let next = index + 1
      guard next < arguments.count, !arguments[next].isEmpty else {
        throw CLIError(message: "\(flag) requires a value")
      }
      index = next
      return arguments[next]
    }

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--host": options.host = try value(after: argument)
      case "--port": options.port = try integer(try value(after: argument), flag: argument)
      case "--model": options.model = try value(after: argument)
      case "--dimensions": options.dimensions = try integer(try value(after: argument), flag: argument)
      case "--chunk-size": options.chunkSize = try integer(try value(after: argument), flag: argument)
      case "--overlap": options.overlap = try integer(try value(after: argument), flag: argument)
      case "--lexical-weight": options.lexicalWeight = try decimal(try value(after: argument), flag: argument)
      case "--mmr-lambda": options.mmrLambda = try decimal(try value(after: argument), flag: argument)
      case "--source-penalty": options.sameSourcePenalty = try decimal(try value(after: argument), flag: argument)
      case "--top-k": options.topK = try integer(try value(after: argument), flag: argument)
      case "--character-budget":
        options.characterBudget = try integer(try value(after: argument), flag: argument)
      case "--split":
        let rawValue = try value(after: argument)
        guard let split = GroundingBenchmarkSplit(rawValue: rawValue) else {
          throw CLIError(message: "--split must be tuning, held-out, or all")
        }
        options.split = split
      case "--output-dir":
        options.outputDirectory = URL(
          fileURLWithPath: try value(after: argument), isDirectory: true)
      case "--allow-remote": options.allowRemote = true
      case "--help", "-h":
        printUsage()
        exit(EXIT_SUCCESS)
      default:
        throw CLIError(message: "Unknown option: \(argument)")
      }
      index += 1
    }
    return options
  }

  private static func integer(_ value: String, flag: String) throws -> Int {
    guard let parsed = Int(value) else {
      throw CLIError(message: "\(flag) requires an integer")
    }
    return parsed
  }

  private static func decimal(_ value: String, flag: String) throws -> Double {
    guard let parsed = Double(value), parsed.isFinite else {
      throw CLIError(message: "\(flag) requires a finite number")
    }
    return parsed
  }

  static func printUsage() {
    print(
      """
      Usage: scripts/run-grounding-benchmark.sh [options]

        --host HOST                 Ollama host (default: 127.0.0.1)
        --port PORT                 Ollama port (default: 11434)
        --model MODEL               Embedding model (default: nomic-embed-text)
        --dimensions COUNT          Optional requested embedding dimensions
        --split tuning|held-out|all Query split (default: held-out)
        --top-k COUNT               Retrieval depth (default: 3)
        --character-budget COUNT    Context budget (default: 2000)
        --chunk-size COUNT          Chunk size (default: 800)
        --overlap COUNT             Chunk overlap (default: 120)
        --lexical-weight VALUE      Hybrid lexical weight (default: 0.15)
        --mmr-lambda VALUE          MMR relevance weight (default: 0.75)
        --source-penalty VALUE      Same-source penalty (default: 0.1)
        --output-dir PATH           Parent directory for an atomic report bundle (default: benchmark-results)
        --allow-remote              Permit sending the public fixture to a non-loopback host
        --help                      Show this help
      """)
  }
}

private struct PublishedBenchmarkReports {
  let directory: URL
  let jsonURL: URL
  let markdownURL: URL
}

/// Publishes both report artifacts as one directory.
///
/// The files are written to a staging directory beside the final directory.
/// The final directory move is the only publication step, so readers never
/// observe one report without the other. FileManager's move operation fails
/// when its destination already exists; the preflight checks provide a
/// clearer error while the move remains the race-safe no-overwrite operation.
private struct BenchmarkReportPublisher {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func publish(
    report: GroundingBenchmarkReport,
    stem: String,
    in outputDirectory: URL
  ) throws -> PublishedBenchmarkReports {
    let jsonData = try report.jsonData()
    let markdownData = Data(report.markdown().utf8)
    try fileManager.createDirectory(
      at: outputDirectory, withIntermediateDirectories: true)

    let finalDirectory = outputDirectory.appendingPathComponent(stem, isDirectory: true)
    let legacyJSONURL = outputDirectory.appendingPathComponent("\(stem).json")
    let legacyMarkdownURL = outputDirectory.appendingPathComponent("\(stem).md")
    guard !fileManager.fileExists(atPath: finalDirectory.path),
      !fileManager.fileExists(atPath: legacyJSONURL.path),
      !fileManager.fileExists(atPath: legacyMarkdownURL.path)
    else {
      throw CLIError(message: "Refusing to overwrite an existing benchmark report named \(stem).")
    }

    let stagingDirectory = outputDirectory.appendingPathComponent(
      ".\(stem).\(UUID().uuidString).partial", isDirectory: true)
    try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: stagingDirectory) }

    let stagedJSONURL = stagingDirectory.appendingPathComponent("report.json")
    let stagedMarkdownURL = stagingDirectory.appendingPathComponent("report.md")
    try jsonData.write(to: stagedJSONURL, options: .atomic)
    try markdownData.write(to: stagedMarkdownURL, options: .atomic)

    // The staging directory is on the same volume as the destination, so
    // this publishes both completed files with one directory move. If a
    // concurrent run wins the destination name after the preflight checks,
    // moveItem throws instead of replacing it.
    try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
    return PublishedBenchmarkReports(
      directory: finalDirectory,
      jsonURL: finalDirectory.appendingPathComponent("report.json"),
      markdownURL: finalDirectory.appendingPathComponent("report.md"))
  }
}

@main
private struct GroundingBenchmarkCLI {
  static func main() async {
    do {
      let options = try BenchmarkCLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
      let endpoint = try OllamaEndpoint(host: options.host, port: options.port)
      guard endpoint.isLoopback || options.allowRemote else {
        throw CLIError(
          message: "Refusing a non-loopback Ollama endpoint without --allow-remote. Ollama transport is HTTP.")
      }

      let client = try OllamaClient(endpoint: endpoint, timeout: 180)
      let installedModels = try await client.fetchModels()
      let installedModel = installedModels.first {
        $0.model == options.model || $0.name == options.model
      }
      guard let installedModel else {
        throw CLIError(
          message: "Embedding model '\(options.model)' is not installed at \(endpoint.baseURL.absoluteString).")
      }
      let canonicalModel = installedModel.model
      if canonicalModel != options.model {
        print("Using installed model '\(canonicalModel)' for requested model '\(options.model)'.")
      }

      let configuration = try GroundingBenchmarkConfiguration(
        embeddingModel: canonicalModel,
        dimensions: options.dimensions,
        chunkSize: options.chunkSize,
        overlap: options.overlap,
        lexicalWeight: options.lexicalWeight,
        mmrLambda: options.mmrLambda,
        sameSourcePenalty: options.sameSourcePenalty,
        topK: options.topK,
        characterBudget: options.characterBudget,
        split: options.split,
        endpointLocality: endpoint.isLoopback ? .local : .remote,
        providerModelVersion: installedModel.digest)
      let runner = GroundingBenchmarkRunner(embeddingProvider: client)
      let report = try await runner.run(configuration: configuration) { progress in
        let query = progress.currentQueryID.map { " (\($0))" } ?? ""
        print("\(progress.phase.rawValue): \(progress.completed)/\(progress.total)\(query)")
      }

      let stem = reportStem(model: canonicalModel, split: options.split)
      let published = try BenchmarkReportPublisher().publish(
        report: report, stem: stem, in: options.outputDirectory)

      print("Grounding benchmark complete")
      print("  hit rate @ \(report.metadata.topK): \(percent(report.aggregate.hitRateAtK))")
      print("  mean recall @ \(report.metadata.topK): \(percent(report.aggregate.recallAtK))")
      print("  source coverage: \(percent(report.aggregate.sourceCoverage))")
      print("  errors / zero results: \(report.aggregate.errorCount) / \(report.aggregate.zeroResultCount)")
      print("  Bundle: \(published.directory.path)")
      print("  JSON: \(published.jsonURL.path)")
      print("  Markdown: \(published.markdownURL.path)")
    } catch is CancellationError {
      writeError("Benchmark cancelled.")
      exit(EXIT_FAILURE)
    } catch {
      writeError(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  private static func reportStem(
    model: String,
    split: GroundingBenchmarkSplit,
    date: Date = Date()
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let safeModel = model.map {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "-"
    }
    return "grounding-\(String(safeModel))-\(split.rawValue)-\(formatter.string(from: date))"
  }

  private static func percent(_ value: Double) -> String {
    String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), value * 100)
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("benchmark: \(message)\n".utf8))
  }
}
