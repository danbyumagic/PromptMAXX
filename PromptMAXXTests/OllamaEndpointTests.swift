import XCTest
@testable import PromptMAXX

final class OllamaEndpointTests: XCTestCase {
    func testAcceptsIPv4HostnameAndIPv6() throws {
        let ipv4 = try OllamaEndpoint(host: "127.0.0.1", port: 11434)
        XCTAssertEqual(ipv4.baseURL.absoluteString, "http://127.0.0.1:11434")

        let hostname = try OllamaEndpoint(host: "ollama.example.test", port: "1234")
        XCTAssertEqual(hostname.host, "ollama.example.test")
        XCTAssertEqual(hostname.port, 1234)

        let ipv6 = try OllamaEndpoint(host: "[::1]", port: 11434)
        XCTAssertEqual(ipv6.host, "::1")
        XCTAssertEqual(ipv6.baseURL.absoluteString, "http://[::1]:11434")

        let compressed = try OllamaEndpoint(host: "2001:db8::1", port: 11434)
        XCTAssertEqual(compressed.host, "2001:db8::1")

        let mapped = try OllamaEndpoint(host: "::ffff:127.0.0.1", port: 11434)
        XCTAssertEqual(mapped.host, "::ffff:127.0.0.1")
    }

    func testDetectsLoopbackHosts() throws {
        XCTAssertTrue(try OllamaEndpoint(host: "localhost").isLoopback)
        XCTAssertTrue(try OllamaEndpoint(host: "localhost.").isLoopback)
        XCTAssertTrue(try OllamaEndpoint(host: "127.0.0.1").isLoopback)
        XCTAssertTrue(try OllamaEndpoint(host: "127.42.9.255").isLoopback)
        XCTAssertTrue(try OllamaEndpoint(host: "[::1]").isLoopback)
        XCTAssertTrue(try OllamaEndpoint(host: "::ffff:127.0.0.1").isLoopback)
        XCTAssertFalse(try OllamaEndpoint(host: "::ffff:192.168.1.10").isLoopback)
        XCTAssertFalse(try OllamaEndpoint(host: "192.168.1.10").isLoopback)
        XCTAssertFalse(try OllamaEndpoint(host: "ollama.example.test").isLoopback)
    }

    func testBuildsValidAPIPaths() throws {
        let endpoint = try OllamaEndpoint(host: "localhost", port: 11434)
        XCTAssertEqual(try endpoint.url(path: "/api/tags").absoluteString, "http://localhost:11434/api/tags")
        XCTAssertEqual(try endpoint.url(path: "/api/generate").path, "/api/generate")
    }

    func testRejectsInvalidPathsAndHosts() throws {
        let endpoint = try OllamaEndpoint(host: "localhost")
        for path in ["", "api/tags", "/api/tags?x=1", "/api/tags#fragment"] {
            XCTAssertThrowsError(try endpoint.url(path: path), "Expected rejection for \(path)")
        }

        for host in [" localhost", "localhost ", "http://localhost", "localhost/path", "", "bad host", "127.0.0.999", "[::1"] {
            XCTAssertThrowsError(try OllamaEndpoint(host: host), "Expected rejection for \(host)")
        }
    }

    func testRejectsMalformedIPv6AndHostLabels() throws {
        for host in ["[::1]extra", "1:::", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9", "[127.0.0.1]", "host..example", "-host.example", "host-.example"] {
            XCTAssertThrowsError(try OllamaEndpoint(host: host), "Expected rejection for \(host)")
        }
    }

    func testRejectsNonnumericAndOutOfRangePorts() throws {
        for port in ["", " 11434", "11434 ", "abc", "0", "65536", "999999"] {
            XCTAssertThrowsError(try OllamaEndpoint(host: "localhost", port: port), "Expected rejection for \(port)")
        }
        for port in [0, -1, 65_536] {
            XCTAssertThrowsError(try OllamaEndpoint(host: "localhost", port: port))
        }
    }
}
