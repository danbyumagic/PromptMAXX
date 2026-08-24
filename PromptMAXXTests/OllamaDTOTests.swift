import XCTest
@testable import PromptMAXX

final class OllamaDTOTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testDecodesRepresentativeTagsResponse() throws {
        let data = Data(#"{"models":[{"name":"phi4-mini:latest","model":"phi4-mini:latest","modified_at":"2026-05-18T12:00:00Z","size":2500000000,"digest":"abc123","details":{"format":"gguf","family":"phi","families":["phi"],"parameter_size":"3.8B","quantization_level":"Q4_K_M"},"expires_at":"0001-01-01T00:00:00Z","size_vram":2400000000}]}"#.utf8)
        let response = try decoder.decode(OllamaTagsResponse.self, from: data)
        XCTAssertEqual(response.models.count, 1)
        XCTAssertEqual(response.models[0].model, "phi4-mini:latest")
        XCTAssertEqual(response.models[0].displayName, "phi4-mini:latest")
        XCTAssertEqual(response.models[0].details?.parameterSize, "3.8B")
        XCTAssertEqual(response.models[0].sizeVRAM, 2_400_000_000)
    }

    func testDecodesGenerateChunksAndErrorPayload() throws {
        let chunkData = Data(#"{"model":"phi4-mini:latest","created_at":"2026-05-18T12:00:00Z","response":"hello","done":false}"#.utf8)
        let finalData = Data(#"{"model":"phi4-mini:latest","response":"","done":true,"done_reason":"stop","context":[1,2],"total_duration":99,"eval_count":2}"#.utf8)
        let chunk = try decoder.decode(OllamaGenerateChunk.self, from: chunkData)
        let final = try decoder.decode(OllamaGenerateChunk.self, from: finalData)
        XCTAssertEqual(chunk.response, "hello")
        XCTAssertEqual(chunk.done, false)
        XCTAssertEqual(final.doneReason, "stop")
        XCTAssertEqual(final.context, [1, 2])
        XCTAssertEqual(final.totalDuration, 99)
    }

    func testEncodesGenerateRequestKeysAndOptions() throws {
        let request = OllamaGenerateRequest(
            model: "phi4-mini",
            prompt: "make it concise",
            stream: true,
            format: .json,
            system: "be direct",
            keepAlive: "5m",
            think: false,
            options: OllamaGenerateOptions(seed: 7, temperature: 0.2, topK: 20, topP: 0.9, numPredict: 64, numCtx: 2048, stop: ["END"]),
            images: ["base64-image"]
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "phi4-mini")
        XCTAssertEqual(object["prompt"] as? String, "make it concise")
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual(object["keep_alive"] as? String, "5m")
        XCTAssertEqual(object["think"] as? Bool, false)
        XCTAssertEqual(object["format"] as? String, "json")
        let options = try XCTUnwrap(object["options"] as? [String: Any])
        XCTAssertEqual(options["top_k"] as? Int, 20)
        XCTAssertEqual(options["num_predict"] as? Int, 64)
        XCTAssertEqual(options["num_ctx"] as? Int, 2048)
    }
}
