import Foundation

nonisolated public enum OllamaEmbedInput: Codable, Sendable, Hashable {
  case text(String)
  case texts([String])
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .text(let value): try container.encode(value)
    case .texts(let values): try container.encode(values)
    }
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .text(value)
    } else {
      self = .texts(try container.decode([String].self))
    }
  }
}

nonisolated public struct OllamaEmbedRequest: Codable, Sendable, Hashable {
  public let model: String
  public let input: OllamaEmbedInput
  public let truncate: Bool?
  public let dimensions: Int?
  public let options: OllamaGenerateOptions?

  public init(
    model: String, input: String, truncate: Bool? = nil, dimensions: Int? = nil,
    options: OllamaGenerateOptions? = nil
  ) {
    self.init(
      model: model, input: .text(input), truncate: truncate, dimensions: dimensions,
      options: options)
  }
  public init(
    model: String, input: [String], truncate: Bool? = nil, dimensions: Int? = nil,
    options: OllamaGenerateOptions? = nil
  ) {
    self.init(
      model: model, input: .texts(input), truncate: truncate, dimensions: dimensions,
      options: options)
  }
  public init(
    model: String, input: OllamaEmbedInput, truncate: Bool? = nil, dimensions: Int? = nil,
    options: OllamaGenerateOptions? = nil
  ) {
    self.model = model
    self.input = input
    self.truncate = truncate
    self.dimensions = dimensions
    self.options = options
  }
}

nonisolated public struct OllamaEmbedResponse: Codable, Sendable, Hashable {
  public let model: String
  public let embeddings: [[Double]]
  public let totalDuration: Int64?
  public let loadDuration: Int64?
  public let promptEvalCount: Int?

  enum CodingKeys: String, CodingKey {
    case model, embeddings
    case totalDuration = "total_duration"
    case loadDuration = "load_duration"
    case promptEvalCount = "prompt_eval_count"
  }
}

nonisolated public struct OllamaTagsResponse: Codable, Sendable {
  public let models: [OllamaModel]

  public init(models: [OllamaModel]) {
    self.models = models
  }
}

nonisolated public struct OllamaModel: Codable, Identifiable, Sendable, Hashable {
  public let model: String
  public let name: String?
  public let modifiedAt: String?
  public let size: Int64?
  public let digest: String?
  public let details: OllamaModelDetails?
  public let expiresAt: String?
  public let sizeVRAM: Int64?

  public var id: String { model }
  public var displayName: String { name ?? model }

  public init(
    model: String,
    name: String? = nil,
    modifiedAt: String? = nil,
    size: Int64? = nil,
    digest: String? = nil,
    details: OllamaModelDetails? = nil,
    expiresAt: String? = nil,
    sizeVRAM: Int64? = nil
  ) {
    self.model = model
    self.name = name
    self.modifiedAt = modifiedAt
    self.size = size
    self.digest = digest
    self.details = details
    self.expiresAt = expiresAt
    self.sizeVRAM = sizeVRAM
  }

  enum CodingKeys: String, CodingKey {
    case model
    case name
    case modifiedAt = "modified_at"
    case size
    case digest
    case details
    case expiresAt = "expires_at"
    case sizeVRAM = "size_vram"
  }
}

nonisolated public struct OllamaModelDetails: Codable, Sendable, Hashable {
  public let parentModel: String?
  public let format: String?
  public let family: String?
  public let families: [String]?
  public let parameterSize: String?
  public let quantizationLevel: String?

  public init(
    parentModel: String? = nil,
    format: String? = nil,
    family: String? = nil,
    families: [String]? = nil,
    parameterSize: String? = nil,
    quantizationLevel: String? = nil
  ) {
    self.parentModel = parentModel
    self.format = format
    self.family = family
    self.families = families
    self.parameterSize = parameterSize
    self.quantizationLevel = quantizationLevel
  }

  enum CodingKeys: String, CodingKey {
    case parentModel = "parent_model"
    case format
    case family
    case families
    case parameterSize = "parameter_size"
    case quantizationLevel = "quantization_level"
  }
}

nonisolated public enum OllamaResponseFormat: String, Codable, Sendable {
  case text
  case json
}

nonisolated public struct OllamaGenerateOptions: Codable, Sendable, Hashable {
  public var seed: Int?
  public var temperature: Double?
  public var topK: Int?
  public var topP: Double?
  public var numPredict: Int?
  public var numCtx: Int?
  public var stop: [String]?

  public init(
    seed: Int? = nil,
    temperature: Double? = nil,
    topK: Int? = nil,
    topP: Double? = nil,
    numPredict: Int? = nil,
    numCtx: Int? = nil,
    stop: [String]? = nil
  ) {
    self.seed = seed
    self.temperature = temperature
    self.topK = topK
    self.topP = topP
    self.numPredict = numPredict
    self.numCtx = numCtx
    self.stop = stop
  }

  enum CodingKeys: String, CodingKey {
    case seed
    case temperature
    case topK = "top_k"
    case topP = "top_p"
    case numPredict = "num_predict"
    case numCtx = "num_ctx"
    case stop
  }
}

nonisolated public struct OllamaGenerateRequest: Codable, Sendable, Hashable {
  public let model: String
  public let prompt: String
  public var stream: Bool
  public var format: OllamaResponseFormat?
  public var system: String?
  public var template: String?
  public var context: [Int]?
  public var raw: Bool?
  public var keepAlive: String?
  public var think: Bool?
  public var options: OllamaGenerateOptions?
  public var images: [String]?

  public init(
    model: String,
    prompt: String,
    stream: Bool = true,
    format: OllamaResponseFormat? = nil,
    system: String? = nil,
    template: String? = nil,
    context: [Int]? = nil,
    raw: Bool? = nil,
    keepAlive: String? = nil,
    think: Bool? = nil,
    options: OllamaGenerateOptions? = nil,
    images: [String]? = nil
  ) {
    self.model = model
    self.prompt = prompt
    self.stream = stream
    self.format = format
    self.system = system
    self.template = template
    self.context = context
    self.raw = raw
    self.keepAlive = keepAlive
    self.think = think
    self.options = options
    self.images = images
  }

  enum CodingKeys: String, CodingKey {
    case model
    case prompt
    case stream
    case format
    case system
    case template
    case context
    case raw
    case keepAlive = "keep_alive"
    case think
    case options
    case images
  }
}

/// A line emitted by `/api/generate`. The final line contains timing and token metadata.
nonisolated public struct OllamaGenerateChunk: Codable, Sendable, Hashable {
  public let model: String?
  public let createdAt: String?
  public let response: String?
  public let thinking: String?
  public let done: Bool?
  public let doneReason: String?
  public let context: [Int]?
  public let totalDuration: Int64?
  public let loadDuration: Int64?
  public let promptEvalCount: Int?
  public let promptEvalDuration: Int64?
  public let evalCount: Int?
  public let evalDuration: Int64?
  public let error: String?

  public init(
    model: String? = nil,
    createdAt: String? = nil,
    response: String? = nil,
    thinking: String? = nil,
    done: Bool? = nil,
    doneReason: String? = nil,
    context: [Int]? = nil,
    totalDuration: Int64? = nil,
    loadDuration: Int64? = nil,
    promptEvalCount: Int? = nil,
    promptEvalDuration: Int64? = nil,
    evalCount: Int? = nil,
    evalDuration: Int64? = nil,
    error: String? = nil
  ) {
    self.model = model
    self.createdAt = createdAt
    self.response = response
    self.thinking = thinking
    self.done = done
    self.doneReason = doneReason
    self.context = context
    self.totalDuration = totalDuration
    self.loadDuration = loadDuration
    self.promptEvalCount = promptEvalCount
    self.promptEvalDuration = promptEvalDuration
    self.evalCount = evalCount
    self.evalDuration = evalDuration
    self.error = error
  }

  enum CodingKeys: String, CodingKey {
    case model
    case createdAt = "created_at"
    case response
    case thinking
    case done
    case doneReason = "done_reason"
    case context
    case totalDuration = "total_duration"
    case loadDuration = "load_duration"
    case promptEvalCount = "prompt_eval_count"
    case promptEvalDuration = "prompt_eval_duration"
    case evalCount = "eval_count"
    case evalDuration = "eval_duration"
    case error
  }
}

nonisolated public struct OllamaErrorPayload: Codable, Sendable, Hashable {
  public let error: String

  public init(error: String) {
    self.error = error
  }
}
