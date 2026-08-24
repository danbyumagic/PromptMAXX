//
//  PromptMAXXApp.swift
//  PromptMAXX
//
//  Created by Daniel Jensen on 5/18/26.
//

import SwiftUI
import Foundation
import CryptoKit

@main
struct PromptMAXXApp: App {
    @State private var store: PromptLibraryStore
    @State private var traceStore: TraceStore
    @State private var groundingStore: GroundingStore?
    @State private var groundingStoreError: String?
    @State private var configuredGroundingEndpointKey: String
    @AppStorage("ollamaHost") private var ollamaHost = "127.0.0.1"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"

    init() {
        let host: String
        let port: String
        let result: (store: GroundingStore?, error: String?)

        if PromptMAXXRuntime.isRunningTests {
            let testDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "PromptMAXX-TestHost-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                    isDirectory: true
                )
            let libraryRepository = PromptLibraryRepository(
                fileURL: testDirectory.appendingPathComponent("prompt-library.json")
            )
            _store = State(
                initialValue: PromptLibraryStore(
                    repository: libraryRepository,
                    userDefaults: .standard,
                    migrationEnabled: false
                )
            )
            _traceStore = State(
                initialValue: TraceStore(
                    repository: TraceRepository(
                        fileURL: testDirectory.appendingPathComponent("traces.json")
                    )
                )
            )
            host = "127.0.0.1"
            port = "11434"
            result = Self.makeGroundingStore(
                host: host,
                port: port,
                repositoryURL: testDirectory.appendingPathComponent("grounding-index.json")
            )
        } else {
            _store = State(initialValue: PromptLibraryStore())
            _traceStore = State(
                initialValue: TraceStore(
                    repository: TraceRepository(fileURL: Self.traceFileURL())
                )
            )
            host = UserDefaults.standard.string(forKey: "ollamaHost") ?? "127.0.0.1"
            port = UserDefaults.standard.string(forKey: "ollamaPort") ?? "11434"
            result = Self.makeGroundingStore(host: host, port: port)
        }

        _groundingStore = State(initialValue: result.store)
        _groundingStoreError = State(initialValue: result.error)
        _configuredGroundingEndpointKey = State(initialValue: Self.endpointKey(host: host, port: port))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                traceStore: traceStore,
                groundingStore: groundingStore,
                groundingStoreError: groundingStoreError
            )
            .task(id: endpointKey) {
                guard PromptMAXXRuntime.automaticNetworkingAllowed else { return }
                guard configuredGroundingEndpointKey != endpointKey else { return }
                let result = Self.makeGroundingStore(host: ollamaHost, port: ollamaPort)
                configuredGroundingEndpointKey = endpointKey
                groundingStore = result.store
                groundingStoreError = result.error
            }
            .frame(minWidth: 760, minHeight: 480)
        }

        Settings {
            SetupView()
        }
    }

    private static func traceFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        return supportDirectory
            .appendingPathComponent("PromptMAXX", isDirectory: true)
            .appendingPathComponent("traces.json", isDirectory: false)
    }

    private var endpointKey: String {
        Self.endpointKey(host: ollamaHost, port: ollamaPort)
    }

    private static func endpointKey(host: String, port: String) -> String {
        "\(host)\u{1F}\(port)"
    }

    private static func makeGroundingStore(
        host: String,
        port: String,
        repositoryURL: URL? = nil
    ) -> (store: GroundingStore?, error: String?) {
        do {
            let endpoint = try OllamaEndpoint(host: host, port: port)
            let client = try OllamaClient(endpoint: endpoint, timeout: 60)
            let repository = try GroundingIndexRepository(
                url: try repositoryURL ?? GroundingIndexLocation.url(for: endpoint))
            let chunker = try GroundingChunker()
            let retriever = try GroundingRetriever()
            let service = try GroundingService(
                embeddingProvider: client,
                repository: repository,
                chunker: chunker,
                retriever: retriever
            )
            return (GroundingStore(service: service), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}

nonisolated enum PromptMAXXRuntime {
    static let testingEnvironmentKey = "PROMPTMAXX_TESTING"
    static let testingArgument = "-PROMPTMAXX_TESTING"
    private static let xctestEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCInjectBundleInto",
        "XCTestSessionIdentifier"
    ]

    static var isRunningTests: Bool {
        isRunningTests(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    static func isRunningTests(environment: [String: String]) -> Bool {
        isRunningTests(environment: environment, arguments: [])
    }

    static func isRunningTests(
        environment: [String: String],
        arguments: [String]
    ) -> Bool {
        if environment[testingEnvironmentKey] == "1" {
            return true
        }

        if arguments.contains("\(testingArgument)=1") {
            return true
        }
        if let argumentIndex = arguments.firstIndex(of: testingArgument),
           arguments.index(after: argumentIndex) < arguments.endIndex,
           arguments[arguments.index(after: argumentIndex)] == "1" {
            return true
        }

        // Hosted XCTest does not consistently propagate TestAction custom
        // environment variables to the application process. These markers
        // are provided by XCTest itself and are therefore a reliable second
        // boundary for lifecycle-triggered work.
        return xctestEnvironmentKeys.contains { key in
            guard let value = environment[key] else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Whether a lifecycle callback may perform automatic provider I/O.
    /// Explicit, user-triggered actions retain their normal networking path.
    static var automaticNetworkingAllowed: Bool {
        !isRunningTests
    }

    static func automaticNetworkingAllowed(environment: [String: String]) -> Bool {
        !isRunningTests(environment: environment)
    }
}

/// Keeps embeddings from different Ollama endpoints in separate opaque files.
/// The endpoint itself is never included in the filename.
nonisolated enum GroundingIndexLocation {
    static func url(
        for endpoint: OllamaEndpoint,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let base = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw GroundingError.invalidURL
        }
        let normalizedEndpoint = endpoint.baseURL.absoluteString.lowercased()
        let digest = SHA256.hash(data: Data(normalizedEndpoint.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return base
            .appendingPathComponent("PromptMAXX", isDirectory: true)
            .appendingPathComponent("grounding-\(digest).json", isDirectory: false)
    }
}
