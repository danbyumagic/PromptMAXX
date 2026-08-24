//
//  ContentView.swift
//  PromptMAXX
//

import SwiftUI
import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Defaults

private let kDefaultSystemPrompt = """
You are a prompt refinement assistant. Convert casual, conversational descriptions into concise, direct AI prompt instructions. Strip personal language. Use direct technical language. Return ONLY the refined prompt — no explanation, no quotes, no preamble.

Input: I want the drums to hit harder
Output: drums should hit harder

Input: I don't like how bright the vocals sound
Output: vocals less bright

Input: the guitar feels too muddy in the low end
Output: reduce guitar low-end muddiness

Input: i don't like the sound the piano is making it sounds too electronic
Output: piano sound should not sound electronic
"""

// MARK: - Content View

private struct RefinementTraceContext: Sendable {
    let runID: UUID
    let startedAt: Date
    let sourceText: String
    let model: String
    let profile: PromptProfile
    let endpointLabel: String
    let endpointLocality: EndpointLocality
    let revisionID: UUID?
    let modelVersion: String?
}

private struct PromptEditorSaveSnapshot: Equatable {
    let documentID: PromptDocument.ID?
    let loadedDocumentID: PromptDocument.ID?
    let originalText: String
    let refinedText: String
    let spec: PromptSpec?
}

private struct PendingRevisionRestore {
    let documentID: PromptDocument.ID
    let revision: PromptRevision
}

struct ContentView: View {
    let store: PromptLibraryStore
    let traceStore: TraceStore
    let groundingStore: GroundingStore?
    let groundingStoreError: String?
    @State private var originalText = ""
    @State private var refinedText = ""
    @State private var selectedID: PromptDocument.ID?
    @State private var loadedDocumentID: PromptDocument.ID?
    @State private var isDirty = false
    @State private var copyFeedback = false
    @State private var saveFeedback = false
    @State private var saveFeedbackID: UUID?
    @State private var saveOperationID: UUID?
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var generationError: String?
    @State private var promptSpec: PromptSpec?
    @State private var generationResult: PromptSpecGenerationResult?
    @State private var generatedProfileName: String?
    @State private var showSpecEditor = false
    @State private var showRunDetails = false
    @State private var showComparisonSetup = false
    @State private var showComparisonResult = false
    @State private var showEvaluationLab = false
    @State private var isComparing = false
    @State private var comparisonTask: Task<Void, Never>?
    @State private var comparisonID: UUID?
    @State private var comparisonResult: PromptComparisonResult?
    @State private var comparisonError: String?
    @State private var showTraceBrowser = false
    @State private var showGroundingInspector = false
    @State private var tracePersistenceError: String?
    @State private var activeRefinementTrace: RefinementTraceContext?
    @State private var showSetup = false
    @AppStorage("selectedModel") private var selectedModel = "phi4-mini:latest"
    @AppStorage("selectedProfileID") private var selectedProfileID = PromptProfile.concise.id
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaHost") private var ollamaHost = "127.0.0.1"
    @AppStorage("systemPrompt") private var systemPrompt = kDefaultSystemPrompt
    @State private var availableModels: [OllamaModel] = []
    @State private var modelRefreshTask: Task<Void, Never>?
    @State private var modelRefreshID: UUID?
    @State private var searchText = ""
    @State private var showRevisionHistory = false
    @State private var historyDocument: PromptDocument?
    @State private var pendingDeleteDocument: PromptDocument?
    @State private var pendingSelectionID: PromptDocument.ID?
    @State private var showDiscardConfirmation = false
    @State private var showNewDiscardConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showRecoveryConfirmation = false
    @State private var pendingRevisionRestore: PendingRevisionRestore?
    @State private var showRevisionRestoreConfirmation = false
    @State private var libraryFeedback: String?

    @MainActor init(
        store: PromptLibraryStore,
        traceStore: TraceStore,
        groundingStore: GroundingStore?,
        groundingStoreError: String? = nil
    ) {
        self.store = store
        self.traceStore = traceStore
        self.groundingStore = groundingStore
        self.groundingStoreError = groundingStoreError
    }

    @MainActor init(store: PromptLibraryStore) {
        self.init(
            store: store,
            traceStore: Self.previewTraceStore(),
            groundingStore: Self.previewGroundingStore()
        )
    }

    @MainActor init() {
        self.init(
            store: Self.previewLibraryStore(),
            traceStore: Self.previewTraceStore(),
            groundingStore: Self.previewGroundingStore()
        )
    }

    private static func previewLibraryStore() -> PromptLibraryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptMAXX-Preview-Library-\(UUID().uuidString)", isDirectory: true)
        let repository = PromptLibraryRepository(
            fileURL: directory.appendingPathComponent("prompt-library.json", isDirectory: false))
        let defaults = UserDefaults(suiteName: "PromptMAXX.Preview.\(UUID().uuidString)") ?? UserDefaults()
        return PromptLibraryStore(repository: repository, userDefaults: defaults)
    }

    private static func previewTraceStore() -> TraceStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptMAXX-Preview-Traces-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("traces.json", isDirectory: false)
        return TraceStore(repository: TraceRepository(fileURL: url))
    }

    private static func previewGroundingStore() -> GroundingStore? {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PromptMAXX-Preview-Grounding-\(UUID().uuidString)", isDirectory: true)
            let repository = try GroundingIndexRepository(
                url: directory.appendingPathComponent("grounding-index.json", isDirectory: false))
            let endpoint = try OllamaEndpoint(host: "127.0.0.1", port: "11434")
            let client = try OllamaClient(endpoint: endpoint, timeout: 60)
            let service = try GroundingService(
                embeddingProvider: client,
                repository: repository,
                chunker: try GroundingChunker(),
                retriever: try GroundingRetriever()
            )
            return GroundingStore(service: service)
        } catch {
            return nil
        }
    }

    private var endpoint: OllamaEndpoint? {
        try? OllamaEndpoint(host: ollamaHost, port: ollamaPort)
    }

    private var availableModelNames: [String] {
        availableModels.map(\.model)
    }

    private var hasSelectedAvailableModel: Bool {
        availableModelNames.contains(selectedModel)
    }

    private var selectedProfile: PromptProfile {
        if selectedProfileID == "custom" {
            return PromptProfile.custom(systemPrompt: systemPrompt)
        }
        return PromptProfile.builtIns.first(where: { $0.id == selectedProfileID }) ?? .concise
    }

    private var selectedProfileDisplayName: String {
        generatedProfileName ?? selectedProfile.name
    }

    private var endpointValidationMessage: String? {
        guard endpoint == nil else { return nil }
        return "Enter a valid host and port to connect to Ollama."
    }

    private var endpointPrivacyLabel: String {
        guard let endpoint else { return "Endpoint unavailable" }
        return endpoint.isLoopback ? "Local Ollama" : "Remote Ollama"
    }

    private var endpointPrivacyDescription: String {
        guard let endpoint else { return "Enter a valid Ollama host and port." }
        let displayHost = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        if endpoint.isLoopback {
            return "Prompts are sent to Ollama on this Mac (\(displayHost):\(endpoint.port))."
        }
        return "Prompts are sent to remote Ollama over HTTP at \(displayHost):\(endpoint.port). Use a trusted network or encrypted tunnel."
    }

    private var canSave: Bool {
        !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !refinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeText: String {
        refinedText.isEmpty ? originalText : refinedText
    }

    private var wordCount: Int {
        activeText.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    var body: some View {
        NavigationSplitView {
            historySidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search library")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        libraryMenu
                    }
                }
        } detail: {
            promptEditor
        }
        .onDisappear {
            cancelGeneration(reason: .viewClosed)
            cancelComparison()
            modelRefreshTask?.cancel()
        }
        .onChange(of: ollamaHost) { _, _ in
            invalidateComparison()
            scheduleModelRefresh()
            showGroundingInspector = false
        }
        .onChange(of: ollamaPort) { _, _ in
            invalidateComparison()
            scheduleModelRefresh()
            showGroundingInspector = false
        }
        .onChange(of: systemPrompt) { _, _ in
            if selectedProfileID == "custom" {
                clearGeneratedArtifacts()
                invalidateComparison()
            }
        }
        .task {
            await store.loadIfNeeded()
            await traceStore.loadIfNeeded()
        }
        .sheet(isPresented: $showRevisionHistory) {
            if let historyDocument {
                PromptRevisionHistoryView(
                    document: historyDocument,
                    onCopy: copyText,
                    onRestore: requestRevisionRestore
                )
            }
        }
        .sheet(isPresented: $showTraceBrowser) {
            TraceBrowserView(store: traceStore)
        }
        .sheet(isPresented: $showGroundingInspector) {
            if let groundingStore {
                GroundingInspectorView(
                    store: groundingStore,
                    isRemoteEndpoint: endpoint.map { !$0.isLoopback } ?? false
                )
                .id(groundingEndpointKey)
            } else {
                groundingUnavailableView
            }
        }
        .alert("Delete Prompt?", isPresented: $showDeleteConfirmation, presenting: pendingDeleteDocument) { document in
            Button("Delete", role: .destructive) {
                pendingDeleteDocument = nil
                deleteDocument(document)
            }
            Button("Cancel", role: .cancel) { pendingDeleteDocument = nil }
        } message: { document in
            Text(deleteConfirmationMessage(for: document))
        }
        .alert("Discard Unsaved Changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard Changes", role: .destructive) {
                guard let pendingSelectionID,
                      let document = store.history.first(where: { $0.id == pendingSelectionID }) else { return }
                self.pendingSelectionID = nil
                loadEntry(document)
            }
            Button("Keep Editing", role: .cancel) { pendingSelectionID = nil }
        } message: {
            Text("Your current editor changes have not been saved.")
        }
        .alert("Start a New Prompt?", isPresented: $showNewDiscardConfirmation) {
            Button("Discard Changes", role: .destructive) { clearEditor() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your current editor changes have not been saved.")
        }
        .alert("Recover Backup?", isPresented: $showRecoveryConfirmation) {
            Button("Recover", role: .destructive) {
                Task {
                    if await store.recoverBackup() {
                        reconcileEditorAfterRecovery()
                        libraryFeedback = "Recovered the last known-good library backup."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recoveryConfirmationMessage)
        }
        .alert("Restore Revision?", isPresented: $showRevisionRestoreConfirmation) {
            Button("Discard Changes", role: .destructive) {
                guard let pendingRevisionRestore else { return }
                self.pendingRevisionRestore = nil
                restoreRevision(
                    documentID: pendingRevisionRestore.documentID,
                    revision: pendingRevisionRestore.revision
                )
            }
            Button("Keep Editing", role: .cancel) {
                pendingRevisionRestore = nil
            }
        } message: {
            Text("This replaces the current editor contents. Your unsaved changes will not be saved.")
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var historySidebar: some View {
        if store.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading Library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("History")
        } else if store.history.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: store.persistenceError == nil ? "clock.arrow.circlepath" : "exclamationmark.triangle")
                    .font(.system(size: 38))
                    .foregroundStyle(.quaternary)
                Text(store.persistenceError == nil ? "No History" : "Library Unavailable")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(store.persistenceError?.localizedDescription ?? "Saved prompts appear here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                if store.persistenceError != nil {
                    Button("Retry") {
                        Task { await store.loadIfNeeded(force: true) }
                    }
                    .buttonStyle(.bordered)
                    if store.hasBackup {
                        Button("Recover Backup…", systemImage: "arrow.counterclockwise.icloud") {
                            showRecoveryConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("History")
        } else {
            let visibleDocuments = store.filteredHistory(search: searchText)
            VStack(spacing: 0) {
                if let persistenceError = store.persistenceError {
                    Label(persistenceError.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1))
                }
                if visibleDocuments.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Prompts", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try a different title, tag, source, or compiled-text search.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(visibleDocuments, selection: $selectedID) { document in
                        HistoryRowView(document: document)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    requestDelete(document)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(store.state != .ready || store.isSaving)
                            }
                            .contextMenu {
                                Button("Load Prompt", systemImage: "arrow.up.doc") {
                                    requestSelection(document.id)
                                }
                                Button(document.isFavorite ? "Remove Favorite" : "Favorite", systemImage: document.isFavorite ? "star.slash" : "star") {
                                    toggleFavorite(document)
                                }
                                .disabled(store.state != .ready || store.isSaving)
                                Button("Revision History", systemImage: "clock.arrow.circlepath") {
                                    showHistory(for: document)
                                }
                                Button("Copy Refined", systemImage: "doc.on.doc") {
                                    copyText(document.displayText)
                                }
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    requestDelete(document)
                                }
                                .disabled(store.state != .ready || store.isSaving)
                            }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                Text("\(visibleDocuments.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .onChange(of: selectedID) { _, newID in
                guard let id = newID else { return }
                requestSelection(id)
            }
        }
    }

    // MARK: Editor

    private var libraryMenu: some View {
        Menu {
            Button("Import Library…", systemImage: "square.and.arrow.down") {
                importLibrary()
            }
            .disabled(store.state != .ready || store.isSaving)
            Button("Export Library…", systemImage: "square.and.arrow.up") {
                exportLibrary()
            }
            .disabled(store.state != .ready || store.isSaving)
            Divider()
            Button("Revision History", systemImage: "clock.arrow.circlepath") {
                if let id = selectedID,
                   let document = store.history.first(where: { $0.id == id }) {
                    showHistory(for: document)
                }
            }
            .disabled(selectedID == nil || store.state != .ready)
        } label: {
            Label("Library", systemImage: "books.vertical")
        }
        .menuStyle(.borderlessButton)
        .help("Import, export, and inspect prompt library history")
    }

    private var promptEditor: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

            VSplitView {
                editorPane(
                    label: "Original",
                    systemImage: "doc.text",
                    text: originalEditorBinding,
                    placeholder: "Paste your raw prompt here…",
                    showProgress: false
                )
                .frame(minHeight: 80)

                editorPane(
                    label: "Refined",
                    systemImage: "wand.and.sparkles",
                    text: refinedEditorBinding,
                    placeholder: isGenerating ? "" : "Write your refined version here…",
                    showProgress: isGenerating
                )
                .frame(minHeight: 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            editorStatusBar
        }
        .background(.background)
        .navigationTitle("PromptMAXX")
        #if os(macOS)
        .navigationSubtitle("AI Prompt Editor")
        #endif
        .task { scheduleModelRefresh(immediate: true) }
    }

    private func editorPane(
        label: String,
        systemImage: String,
        text: Binding<String>,
        placeholder: String,
        showProgress: Bool
    ) -> some View {
        VStack(spacing: 0) {
            // Pane header
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                Button {
                    copyText(text.wrappedValue)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Copy \(label)")
                .opacity(text.wrappedValue.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.quinary)

            if showProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
            } else {
                Divider()
            }

            // The ZStack outer padding is shared by both TextEditor and placeholder,
            // so the placeholder only needs to offset by the TextEditor's internal
            // lineFragmentPadding (~5pt) and textContainerInset (~2pt top).
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(.body, design: .rounded))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)

                if text.wrappedValue.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.leading, 5)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var modelPicker: some View {
        Menu {
            if availableModels.isEmpty {
                Label("Ollama not running", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Divider()
                Button("Refresh models", systemImage: "arrow.clockwise") {
                    scheduleModelRefresh(immediate: true)
                }
                Button("Setup instructions…") { showSetup = true }
            } else {
                ForEach(availableModels) { model in
                    Button {
                        selectedModel = model.model
                        invalidateComparison()
                    } label: {
                        if model.model == selectedModel {
                            Label(modelShortName(model.model), systemImage: "checkmark")
                        } else {
                            Text(modelShortName(model.model))
                        }
                    }
                }
                Divider()
                Button("Refresh list", systemImage: "arrow.clockwise") {
                    scheduleModelRefresh(immediate: true)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                    .foregroundStyle(availableModels.isEmpty ? .tertiary : .secondary)
                Text(availableModels.isEmpty ? "No model" : modelShortName(selectedModel))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(availableModels.isEmpty ? .tertiary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isComparing)
    }

    private var profilePicker: some View {
        Menu {
            ForEach(PromptProfile.builtIns) { profile in
                Button {
                    selectedProfileID = profile.id
                    clearGeneratedArtifacts()
                    invalidateComparison()
                } label: {
                    if profile.id == selectedProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            Divider()
            Button {
                selectedProfileID = "custom"
                clearGeneratedArtifacts()
                invalidateComparison()
            } label: {
                if selectedProfileID == "custom" {
                    Label("Custom", systemImage: "checkmark")
                } else {
                    Text("Custom")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(selectedProfile.name)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isComparing)
        .help("Refinement profile: \(selectedProfile.description)")
    }

    private var endpointPrivacyBadge: some View {
        Label(
            endpointPrivacyLabel,
            systemImage: endpoint?.isLoopback == true ? "lock.fill" : "network"
        )
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(endpoint?.isLoopback == true ? .green : .orange)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .fixedSize()
        .layoutPriority(1)
        .help(endpointPrivacyDescription)
        .accessibilityLabel(endpointPrivacyLabel)
        .accessibilityValue(endpointPrivacyDescription)
    }

    private func modelShortName(_ name: String) -> String {
        name.replacingOccurrences(of: ":latest", with: "")
    }

    private func scheduleModelRefresh(immediate: Bool = false) {
        // Model discovery is lifecycle-triggered here; hosted XCTest must not
        // turn it into a real request to the user's configured Ollama.
        guard PromptMAXXRuntime.automaticNetworkingAllowed else { return }
        modelRefreshTask?.cancel()
        let refreshID = UUID()
        modelRefreshID = refreshID
        modelRefreshTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await fetchModels(refreshID: refreshID)
            if modelRefreshID == refreshID {
                modelRefreshTask = nil
            }
        }
    }

    private func fetchModels(refreshID: UUID) async {
        guard refreshID == modelRefreshID else { return }
        guard let endpoint else {
            availableModels = []
            return
        }
        do {
            let client = try OllamaClient(endpoint: endpoint, timeout: 4)
            let models = try await client.fetchModels().sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
            guard !Task.isCancelled, refreshID == modelRefreshID else { return }
            availableModels = models
            if let first = models.first, !models.contains(where: { $0.model == selectedModel }) {
                selectedModel = first.model
                invalidateComparison()
            }
        } catch {
            guard !Task.isCancelled, refreshID == modelRefreshID else { return }
            availableModels = []
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Button(action: requestNew) {
                Label("New", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("n", modifiers: .command)
            .help("New prompt  ⌘N")

            Spacer()

            endpointPrivacyBadge

            // Model picker
            modelPicker

            // Refinement profile
            profilePicker

            // AI Refine button
            Button {
                if isGenerating {
                    cancelGeneration(reason: .userRequested)
                } else {
                    refineWithAI()
                }
            } label: {
                Label(
                    isGenerating ? "Stop" : "Refine",
                    systemImage: isGenerating ? "stop.circle.fill" : "wand.and.sparkles"
                )
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .tint(isGenerating ? .orange : .purple)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isGenerating && (isComparing || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endpoint == nil || !hasSelectedAvailableModel))
            .help(isGenerating ? "Stop generation  ⌘↩" : "Refine with \(selectedModel) via Ollama  ⌘↩")

            Menu {
                Button {
                    showSpecEditor = true
                } label: {
                    Label("Edit Spec", systemImage: "list.bullet.rectangle")
                }
            .disabled(promptSpec == nil || isGenerating || isComparing)

                Button {
                    showRunDetails = true
                } label: {
                    Label("Run Details", systemImage: "chart.bar.doc.horizontal")
                }
                .disabled(generationResult == nil || isComparing)

                Button {
                    showTraceBrowser = true
                } label: {
                    Label("Run Traces", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    showGroundingInspector = true
                } label: {
                    Label("Context Inspector", systemImage: "text.magnifyingglass")
                }
                .help("Inspect indexed context and retrieval signals")

                Divider()

                Button {
                    if isComparing {
                        cancelComparison()
                    } else {
                        showComparisonSetup = true
                    }
                } label: {
                    Label(
                        isComparing ? "Stop Comparison" : "Compare Candidates",
                        systemImage: isComparing ? "stop.circle" : "square.split.2x1"
                    )
                }
                .disabled(!isComparing && (isGenerating || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endpoint == nil || availableModels.isEmpty))

                Button {
                    showEvaluationLab = true
                } label: {
                    Label("Evaluation Lab", systemImage: "checklist")
                }
                .disabled(isGenerating || isComparing)
            } label: {
                Label(isComparing ? "Comparing…" : "Details", systemImage: isComparing ? "hourglass" : "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Edit the structured prompt or view run details")

            Button(action: saveToHistory) {
                Label(
                    saveFeedback ? "Saved!" : "Save",
                    systemImage: saveFeedback ? "checkmark.circle.fill" : "bookmark"
                )
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .tint(saveFeedback ? .green : nil)
            .disabled(
                store.state != .ready || isGenerating || isComparing || store.isSaving ||
                !canSave || (selectedID != nil && !isDirty)
            )
            .help("Save both fields to history")

            Button(action: copyToClipboard) {
                Label(
                    copyFeedback ? "Copied!" : "Copy Refined",
                    systemImage: copyFeedback ? "checkmark.circle.fill" : "doc.on.doc"
                )
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderedProminent)
            .tint(copyFeedback ? .green : .accentColor)
            .disabled(activeText.isEmpty)
            .help("Copy refined prompt (falls back to original)")

            Divider()
                .frame(height: 16)

            Button { showSetup = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Setup instructions")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .sheet(isPresented: $showSetup) {
            SetupView()
                .onDisappear { scheduleModelRefresh(immediate: true) }
        }
        .sheet(isPresented: $showSpecEditor) {
            if let promptSpec {
                PromptSpecEditorView(spec: promptSpec, profileName: selectedProfileDisplayName) { editedSpec in
                    applyEditedSpec(editedSpec)
                }
            }
        }
        .sheet(isPresented: $showRunDetails) {
            if let generationResult {
                PromptRunSummaryView(result: generationResult, profileName: selectedProfileDisplayName)
            }
        }
        .sheet(isPresented: $showComparisonSetup) {
            PromptComparisonSetupView(
                sourceText: originalText,
                models: availableModels,
                preferredModel: selectedModel,
                customProfile: PromptProfile.custom(systemPrompt: systemPrompt),
                endpointDescription: endpointPrivacyDescription,
                onStart: startComparison
            )
        }
        .sheet(isPresented: $showComparisonResult) {
            if let comparisonResult {
                PromptComparisonView(result: comparisonResult)
            }
        }
        .sheet(isPresented: $showEvaluationLab) {
            EvaluationLabView(
                endpoint: endpoint,
                models: availableModels,
                preferredModel: selectedModel,
                endpointDescription: endpointPrivacyDescription,
                traceStore: traceStore
            )
        }
    }

    private var groundingEndpointKey: String {
        "\(ollamaHost)\u{1F}\(ollamaPort)"
    }

    private var groundingUnavailableView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Context Inspector unavailable", systemImage: "exclamationmark.triangle")
                .font(.title3.bold())
            Text(groundingStoreError ?? endpointValidationMessage ?? "The grounding service could not be configured.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Check the Ollama host and port in Setup, then reopen the inspector.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Close") { showGroundingInspector = false }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Close Context Inspector error")
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 220, alignment: .leading)
    }

    private var editorStatusBar: some View {
        HStack {
            if let id = selectedID,
               let document = store.history.first(where: { $0.id == id }) {
                HStack(spacing: 5) {
                    Image(systemName: isDirty ? "pencil.circle" : "bookmark.fill")
                        .font(.caption2)
                    Text(isDirty
                         ? "Unsaved changes · revision \(document.revisionCount)"
                         : "Saved \(document.updatedAt, style: .relative) · revision \(document.revisionCount)")
                }
                .font(.caption)
                .foregroundStyle(isDirty ? .orange : .secondary)
            }

            Spacer()

            if let comparisonError, !isComparing {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(comparisonError)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.orange)
                .help(comparisonError)
            } else if let generationError, !isGenerating {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(generationError)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.orange)
                .help(generationError)
            } else if isComparing {
                HStack(spacing: 4) {
                    Image(systemName: "square.split.2x1")
                        .font(.caption2)
                    Text("Comparing candidates…")
                        .font(.caption)
                }
                .foregroundStyle(.purple.opacity(0.8))
                .transition(.opacity)
            } else if isGenerating {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.caption2)
                    Text("Structuring…")
                        .font(.caption)
                }
                .foregroundStyle(.purple.opacity(0.8))
                .transition(.opacity)
            } else if store.isSaving {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Saving library…")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else if let libraryFeedback {
                Label(libraryFeedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if let persistenceError = store.persistenceError {
                Text(persistenceError.localizedDescription)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.orange)
                    .help(persistenceError.localizedDescription)
            } else if let tracePersistenceError {
                Text(tracePersistenceError)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.orange)
                    .help(tracePersistenceError)
            } else if let generationResult {
                Text(runMetricsSummary(generationResult.metrics))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                if let endpointValidationMessage {
                    Text(endpointValidationMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if availableModels.isEmpty {
                    Text("No available models — open Setup to connect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(wordCount) words · \(activeText.count) chars")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: isGenerating)
    }

    // MARK: Actions

    private var recoveryConfirmationMessage: String {
        let base = "The corrupt library will be preserved beside the recovered backup before replacement."
        return isDirty ? base + " Your unsaved editor changes will remain in the editor, but the library selection may change." : base
    }

    private func deleteConfirmationMessage(for document: PromptDocument) -> String {
        let base = "Delete \"\(document.title)\" and all \(document.revisionCount) retained revisions? This cannot be undone from the library."
        guard isDirty, loadedDocumentID == document.id else { return base }
        return base + " Your unsaved editor changes for this document will not be saved."
    }

    private func reconcileEditorAfterRecovery() {
        let currentID = selectedID ?? loadedDocumentID
        guard let currentID else { return }
        guard let document = store.history.first(where: { $0.id == currentID }) else {
            invalidatePendingSave()
            selectedID = nil
            loadedDocumentID = nil
            if !isDirty {
                originalText = ""
                refinedText = ""
                clearGeneratedArtifacts()
            }
            return
        }
        guard !isDirty else { return }
        loadEntry(document)
    }

    private func requestNew() {
        guard isDirty else {
            clearEditor()
            return
        }
        invalidatePendingSave()
        showNewDiscardConfirmation = true
    }

    private func clearEditor() {
        invalidatePendingSave()
        cancelGeneration(reason: .promptReplaced)
        cancelComparison()
        clearGeneratedArtifacts()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            originalText = ""
            refinedText = ""
            selectedID = nil
            loadedDocumentID = nil
            isDirty = false
        }
    }

    private func loadEntry(_ document: PromptDocument) {
        invalidatePendingSave()
        cancelGeneration(reason: .promptReplaced)
        cancelComparison()
        guard let revision = document.latestRevision else { return }
        selectedID = document.id
        loadedDocumentID = document.id
        originalText = revision.sourceText
        refinedText = revision.compiledText ?? ""
        promptSpec = revision.spec
        generationResult = nil
        generatedProfileName = revision.profileID.flatMap { id in
            PromptProfile.builtIns.first(where: { $0.id == id })?.name
        }
        generationError = nil
        isDirty = false
    }

    private func requestSelection(_ id: PromptDocument.ID) {
        guard let document = store.history.first(where: { $0.id == id }) else { return }
        guard loadedDocumentID != id else { return }
        guard isDirty else {
            loadEntry(document)
            return
        }
        invalidatePendingSave()
        pendingSelectionID = id
        selectedID = loadedDocumentID
        showDiscardConfirmation = true
    }

    private func showHistory(for document: PromptDocument) {
        historyDocument = document
        showRevisionHistory = true
    }

    private func requestRevisionRestore(
        documentID: PromptDocument.ID,
        revision: PromptRevision
    ) {
        guard store.history.contains(where: { $0.id == documentID }) else {
            libraryFeedback = "That prompt is no longer available in the library."
            return
        }
        guard isDirty else {
            restoreRevision(documentID: documentID, revision: revision)
            return
        }
        pendingRevisionRestore = PendingRevisionRestore(documentID: documentID, revision: revision)
        showRevisionRestoreConfirmation = true
    }

    private func restoreRevision(
        documentID: PromptDocument.ID,
        revision: PromptRevision
    ) {
        invalidatePendingSave()
        cancelGeneration(reason: .promptReplaced)
        cancelComparison()
        selectedID = documentID
        loadedDocumentID = documentID
        originalText = revision.sourceText
        refinedText = revision.compiledText ?? ""
        promptSpec = revision.spec
        generationResult = nil
        generatedProfileName = revision.profileID.flatMap { id in
            PromptProfile.builtIns.first(where: { $0.id == id })?.name
        }
        generationError = nil
        isDirty = true
    }

    private var originalEditorBinding: Binding<String> {
        Binding(
            get: { originalText },
            set: { newValue in
                invalidatePendingSave()
                if isGenerating { cancelGeneration(reason: .promptReplaced) }
                if isComparing { cancelComparison() }
                originalText = newValue
                clearGeneratedArtifacts()
                invalidateComparisonArtifacts()
                isDirty = true
            }
        )
    }

    private var refinedEditorBinding: Binding<String> {
        Binding(
            get: { refinedText },
            set: { newValue in
                invalidatePendingSave()
                if isGenerating { cancelGeneration(reason: .promptReplaced) }
                if isComparing { cancelComparison() }
                refinedText = newValue
                clearGeneratedArtifacts()
                invalidateComparisonArtifacts()
                isDirty = true
            }
        )
    }

    private func clearGeneratedArtifacts() {
        promptSpec = nil
        generationResult = nil
        generatedProfileName = nil
        generationError = nil
    }

    private func invalidateComparisonArtifacts() {
        comparisonResult = nil
        comparisonError = nil
        showComparisonResult = false
    }

    private func invalidateComparison() {
        cancelComparison()
    }

    private func runMetricsSummary(_ metrics: RunMetrics) -> String {
        var parts: [String] = []
        if let duration = metrics.totalDurationMilliseconds {
            parts.append(String(format: "%.0f ms", duration))
        }
        if let input = metrics.inputTokenCount, let output = metrics.outputTokenCount {
            parts.append("\(input) in · \(output) out tokens")
        } else if let output = metrics.outputTokenCount {
            parts.append("\(output) output tokens")
        }
        return parts.isEmpty ? "Structured prompt ready" : parts.joined(separator: " · ")
    }

    private func startComparison(_ configuration: PromptComparisonConfiguration) {
        guard let targetEndpoint = endpoint else {
            comparisonError = "Invalid Ollama settings. Open Setup and check host and port."
            return
        }

        cancelComparison()
        let runID = UUID()
        comparisonID = runID
        isComparing = true
        comparisonError = nil
        let comparisonEndpointLabel = endpointPrivacyDescription
        let comparisonEndpointLocality: EndpointLocality =
            targetEndpoint.isLoopback ? .local : .remote

        comparisonTask = Task {
            do {
                let client = try OllamaClient(endpoint: targetEndpoint, timeout: 60)
                let runner = try PromptComparisonRunner(provider: client, maxConcurrent: 1)
                let result = await runner.compare(configuration)
                guard TracePersistenceGate.permits(
                    capturedToken: runID, activeToken: comparisonID, isCancelled: Task.isCancelled
                ) else { return }
                await recordComparisonTraces(
                    result,
                    endpointLabel: comparisonEndpointLabel,
                    endpointLocality: comparisonEndpointLocality,
                    runID: runID
                )
                guard TracePersistenceGate.permits(
                    capturedToken: runID, activeToken: comparisonID, isCancelled: Task.isCancelled
                ) else { return }
                comparisonResult = result
                showComparisonResult = true
            } catch is CancellationError {
                // The user changed the source/settings or explicitly stopped comparison.
            } catch {
                if comparisonID == runID {
                    comparisonError = "Comparison failed: \(error.localizedDescription)"
                }
            }

            guard comparisonID == runID else { return }
            comparisonID = nil
            isComparing = false
            comparisonTask = nil
        }
    }

    private func recordComparisonTraces(
        _ result: PromptComparisonResult,
        endpointLabel: String,
        endpointLocality: EndpointLocality,
        runID: UUID
    ) async {
        guard TracePersistenceGate.permits(
            capturedToken: runID, activeToken: comparisonID, isCancelled: Task.isCancelled
        ) else { return }
        let traces: [RunTrace]
        do {
            traces = try RunTraceFactory.comparisonBatch(
                result: result,
                endpointLabel: endpointLabel,
                endpointLocality: endpointLocality
            )
        } catch {
            // Build the complete batch before touching the repository. A
            // malformed terminal candidate must never leave a partial batch.
            tracePersistenceError = "Could not record comparison trace: \(error.localizedDescription)"
            return
        }
        guard !traces.isEmpty else { return }
        guard TracePersistenceGate.permits(
            capturedToken: runID, activeToken: comparisonID, isCancelled: Task.isCancelled
        ) else { return }
        // This is the final stale/cancellation gate. Invoking the serialized
        // append below starts the durable operation; later cancellation does
        // not retract completed comparison evidence.
        guard await traceStore.append(contentsOf: traces) else {
            guard comparisonID == runID, !Task.isCancelled else { return }
            tracePersistenceError = traceStore.error?.localizedDescription
                ?? "Trace storage is unavailable."
            return
        }
        if comparisonID == runID, !Task.isCancelled { tracePersistenceError = nil }
    }

    private func refineWithAI() {
        let source = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, let targetEndpoint = endpoint, hasSelectedAvailableModel else { return }

        cancelGeneration(reason: .superseded)
        clearGeneratedArtifacts()
        let runID = UUID()
        generationID = runID
        isGenerating = true
        generationError = nil
        // Keep the selected document identity; the generated result becomes a
        // dirty candidate for its next append-only revision.
        isDirty = true
        refinedText = ""

        let profile = selectedProfile
        let modelName = selectedModel
        let traceContext = RefinementTraceContext(
            runID: runID,
            startedAt: Date(),
            sourceText: source,
            model: modelName,
            profile: profile,
            endpointLabel: endpointPrivacyDescription,
            endpointLocality: targetEndpoint.isLoopback ? .local : .remote,
            revisionID: selectedID.flatMap { id in
                store.history.first(where: { $0.id == id })?.latestRevision?.id
            },
            modelVersion: availableModels.first(where: { $0.model == modelName })?.digest
        )
        activeRefinementTrace = traceContext
        generationTask = Task {
            do {
                let client = try OllamaClient(endpoint: targetEndpoint, timeout: 60)
                let engine = RefinementEngine(provider: client)
                let result = try await engine.generate(
                    model: modelName,
                    sourceText: source,
                    profile: profile,
                    specID: UUID()
                )

                try Task.checkCancellation()
                guard generationID == runID else { return }
                activeRefinementTrace = nil
                recordSuccessfulRefinement(result, context: traceContext)
                promptSpec = result.spec
                generationResult = result
                generatedProfileName = profile.name
                refinedText = result.compiledPrompt
            } catch is CancellationError {
                guard generationID == runID else { return }
                recordRefinementCancellation(traceContext, reason: .unknown)
                activeRefinementTrace = nil
            } catch let error as PromptSpecGenerationError {
                if generationID == runID {
                    recordRefinementFailure(traceContext, error: error)
                    activeRefinementTrace = nil
                    generationError = generationErrorMessage(error)
                }
            } catch {
                if generationID == runID {
                    recordRefinementFailure(traceContext, error: error)
                    activeRefinementTrace = nil
                    generationError = generationErrorMessage(error)
                }
            }

            guard generationID == runID else { return }
            activeRefinementTrace = nil
            generationID = nil
            isGenerating = false
            generationTask = nil
        }
    }

    private func applyEditedSpec(_ editedSpec: PromptSpec) {
        do {
            let normalized = editedSpec.normalized
            let compiled = try PromptCompiler.compile(normalized)
            invalidatePendingSave()
            promptSpec = normalized
            refinedText = compiled

            if let result = generationResult {
                generationResult = PromptSpecGenerationResult(
                    spec: normalized,
                    compiledPrompt: compiled,
                    rawResponse: result.rawResponse,
                    attemptCount: result.attemptCount,
                    model: result.model,
                    profileID: result.profileID,
                    startedAt: result.startedAt,
                    finishedAt: result.finishedAt,
                    metrics: result.metrics
                )
            }
            generationError = nil
            isDirty = true
        } catch {
            generationError = "The edited spec is incomplete. Add an objective and output contract."
        }
    }

    private func generationErrorMessage(_ error: Error) -> String {
        if let specError = error as? PromptSpecGenerationError {
            switch specError {
            case .provider(let message):
                return "Ollama generation failed: \(message)"
            case .invalidProfile, .invalidSpec, .compilation, .malformedJSON, .emptyResponse:
                return "Could not structure the prompt. Try again or edit the profile."
            case .emptySource:
                return "Enter a prompt before refining."
            case .emptyModel:
                return "Select an installed model before refining."
            case .cancelled:
                return "Prompt generation was cancelled."
            }
        }
        guard let ollamaError = error as? OllamaClientError else {
            return "Refinement failed. Check Ollama in Setup and try again."
        }
        switch ollamaError {
        case .invalidEndpoint, .invalidPort:
            return "Invalid Ollama settings. Open Setup and check host and port."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Ollama rejected the request (HTTP \(code)): \(message)"
            }
            return "Ollama rejected the request (HTTP \(code)). Check the selected model."
        case .server(let message):
            return "Ollama error: \(message)"
        case .timedOut:
            return "Ollama timed out. Check the server and try again."
        case .transport:
            return "Can’t reach Ollama. Start it with `ollama serve` and check Setup."
        case .invalidRequest, .invalidResponse, .decoding:
            return "Ollama returned an unusable response. Check the server and try again."
        case .protocolError, .responseTooLarge:
            return "Ollama returned an unusable response. Check the server and try again."
        }
    }

    private func recordSuccessfulRefinement(
        _ result: PromptSpecGenerationResult,
        context: RefinementTraceContext
    ) {
        do {
            let trace = try RunTraceFactory.refinement(
                result: result,
                sourceText: context.sourceText,
                profile: context.profile,
                endpointLabel: context.endpointLabel,
                endpointLocality: context.endpointLocality,
                modelVersion: context.modelVersion,
                revisionID: context.revisionID,
                runID: context.runID
            )
            persistTrace(trace)
        } catch {
            tracePersistenceError = "Could not record refinement trace: \(error.localizedDescription)"
        }
    }

    private func recordRefinementFailure(
        _ context: RefinementTraceContext,
        error: Error
    ) {
        do {
            let trace = try RunTraceFactory.refinementFailed(
                runID: context.runID,
                startedAt: context.startedAt,
                finishedAt: Date(),
                model: context.model,
                profile: context.profile,
                sourceText: context.sourceText,
                endpointLabel: context.endpointLabel,
                endpointLocality: context.endpointLocality,
                error: runError(for: error),
                modelVersion: context.modelVersion,
                revisionID: context.revisionID
            )
            persistTrace(trace)
        } catch {
            tracePersistenceError = "Could not record refinement trace: \(error.localizedDescription)"
        }
    }

    private func recordRefinementCancellation(
        _ context: RefinementTraceContext,
        reason: RunCancellationReason
    ) {
        do {
            let trace = try RunTraceFactory.refinementCancelled(
                runID: context.runID,
                startedAt: context.startedAt,
                finishedAt: Date(),
                model: context.model,
                profile: context.profile,
                sourceText: context.sourceText,
                endpointLabel: context.endpointLabel,
                endpointLocality: context.endpointLocality,
                reason: reason,
                modelVersion: context.modelVersion,
                revisionID: context.revisionID
            )
            persistTrace(trace)
        } catch {
            tracePersistenceError = "Could not record refinement trace: \(error.localizedDescription)"
        }
    }

    private func runError(for error: Error) -> RunError {
        let nsError = error as NSError
        return RunError(domain: nsError.domain, code: nsError.code, message: nsError.localizedDescription)
    }

    private func persistTrace(_ trace: RunTrace) {
        Task { @MainActor in
            guard await traceStore.append(trace) else {
                tracePersistenceError = traceStore.error?.localizedDescription
                    ?? "Trace storage is unavailable."
                return
            }
            tracePersistenceError = nil
        }
    }

    private func cancelGeneration(reason: RunCancellationReason) {
        if let context = activeRefinementTrace {
            recordRefinementCancellation(context, reason: reason)
            activeRefinementTrace = nil
        }
        generationID = nil
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func cancelComparison() {
        comparisonID = nil
        comparisonTask?.cancel()
        comparisonTask = nil
        isComparing = false
        invalidateComparisonArtifacts()
    }

    private func invalidatePendingSave() {
        saveOperationID = nil
        saveFeedbackID = nil
        saveFeedback = false
    }

    private func saveToHistory() {
        guard store.state == .ready,
              !isGenerating,
              !isComparing,
              !store.isSaving,
              canSave,
              selectedID == nil || isDirty
        else { return }

        let operationID = UUID()
        saveOperationID = operationID
        saveFeedbackID = nil
        saveFeedback = false
        let snapshot = PromptEditorSaveSnapshot(
            documentID: selectedID,
            loadedDocumentID: loadedDocumentID,
            originalText: originalText,
            refinedText: refinedText,
            spec: promptSpec
        )
        let run = generationResult
        let generatedModelVersion = run.flatMap { result in
            availableModels.first(where: { $0.model == result.model })?.digest
        }
        let profile = run == nil ? nil : selectedProfile
        let changeSummary = isDirty ? "Saved editor changes" : "Saved prompt"
        Task {
            let document = await store.saveEditor(
                documentID: snapshot.documentID,
                originalText: snapshot.originalText,
                refinedText: snapshot.refinedText,
                spec: snapshot.spec,
                profile: profile,
                modelName: run?.model,
                modelVersion: generatedModelVersion,
                changeSummary: changeSummary
            )

            guard saveOperationID == operationID else { return }
            guard let document else {
                saveOperationID = nil
                return
            }
            let currentSnapshot = PromptEditorSaveSnapshot(
                documentID: selectedID,
                loadedDocumentID: loadedDocumentID,
                originalText: originalText,
                refinedText: refinedText,
                spec: promptSpec
            )
            guard currentSnapshot == snapshot else {
                saveOperationID = nil
                return
            }
            selectedID = document.id
            loadedDocumentID = document.id
            isDirty = false
            saveOperationID = nil
            saveFeedbackID = operationID
            withAnimation(.spring(response: 0.3)) { saveFeedback = true }
            try? await Task.sleep(for: .seconds(1.5))
            guard saveFeedbackID == operationID else { return }
            saveFeedbackID = nil
            withAnimation(.spring(response: 0.3)) { saveFeedback = false }
        }
    }

    private func requestDelete(_ document: PromptDocument) {
        guard store.state == .ready, !store.isSaving else { return }
        pendingDeleteDocument = document
        showDeleteConfirmation = true
    }

    private func deleteDocument(_ document: PromptDocument) {
        guard store.state == .ready, !store.isSaving else { return }
        Task {
            let deleted = await store.deleteDocument(id: document.id)
            guard deleted else { return }
            if selectedID == document.id {
                clearEditor()
            }
        }
    }

    private func toggleFavorite(_ document: PromptDocument) {
        guard store.state == .ready, !store.isSaving else { return }
        let favorite = !document.isFavorite
        Task {
            if await store.setFavorite(favorite, for: document.id) {
                showLibraryFeedback(favorite ? "Added to Favorites." : "Removed from Favorites.")
            }
        }
    }

    private func importLibrary() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if await store.importLibrary(from: url) {
                showLibraryFeedback("Library imported and merged.")
            }
        }
        #endif
    }

    private func exportLibrary() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PromptMAXX-library.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if await store.exportLibrary(to: url) {
                showLibraryFeedback("Library exported.")
            }
        }
        #endif
    }

    private func showLibraryFeedback(_ message: String) {
        libraryFeedback = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if libraryFeedback == message {
                libraryFeedback = nil
            }
        }
    }

    private func copyToClipboard() {
        copyText(activeText)
    }

    private func copyText(_ value: String) {
        guard !value.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
        withAnimation(.spring(response: 0.3)) { copyFeedback = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation(.spring(response: 0.3)) { copyFeedback = false }
            }
        }
    }
}

// MARK: - History Row

struct HistoryRowView: View {
    let document: PromptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 4) {
                if document.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                if document.latestRevision?.compiledText?.isEmpty == false {
                    Image(systemName: "wand.and.sparkles")
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.8))
                }
                Text(document.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                Text("\(document.wordCount)w · r\(document.revisionCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Setup View

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: OllamaStatus = .checking
    @State private var statusTask: Task<Void, Never>?
    @State private var statusRequestID: UUID?
    @State private var showDiagnostics = false
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaHost") private var ollamaHost = "127.0.0.1"
    @AppStorage("selectedModel") private var selectedModel = "phi4-mini:latest"
    @AppStorage("systemPrompt") private var systemPrompt = kDefaultSystemPrompt

    private var endpoint: OllamaEndpoint? {
        try? OllamaEndpoint(host: ollamaHost, port: ollamaPort)
    }

    private var endpointPrivacyNotice: String {
        guard let endpoint else {
            return "Enter a valid host and port to check an Ollama endpoint."
        }
        if endpoint.isLoopback {
            return "Local endpoint: prompt text and model requests stay on this Mac at \(endpoint.host):\(endpoint.port)."
        }
        return "Remote endpoint: prompt text and model requests are sent over HTTP to \(endpoint.host):\(endpoint.port). Use a trusted network or encrypted tunnel."
    }

    enum OllamaStatus {
        case checking, ready, notRunning, noModel, invalidEndpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Setup Ollama")
                        .font(.title2.bold())
                    Text(endpointPrivacyNotice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 22)

            Divider()
                .padding(.bottom, 22)

            // Steps
            VStack(alignment: .leading, spacing: 20) {
                SetupStep(
                    number: 1,
                    title: "Install Ollama",
                    detail: "A lightweight local model server for Apple Silicon.",
                    commands: ["brew install ollama"],
                    footnote: "No Homebrew? Download the installer at ollama.com"
                )
                SetupStep(
                    number: 2,
                    title: "Start the server",
                    detail: "Keep this running on the port configured below.",
                    commands: ["ollama serve"]
                )
                SetupStep(
                    number: 3,
                    title: "Pull models",
                    detail: "Download a generation model and the Context Inspector embedding model.",
                    commands: [
                        "ollama pull phi4-mini:latest",
                        "ollama pull nomic-embed-text"
                    ]
                )
            }
            .padding(.bottom, 22)

            Divider()
                .padding(.bottom, 16)

            // Connection fields
            HStack(spacing: 12) {
                Text("Host")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 34, alignment: .trailing)
                TextField("127.0.0.1", text: $ollamaHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .font(.system(.callout, design: .monospaced))
                    .onChange(of: ollamaHost) { _, _ in scheduleStatusCheck() }

                Text("Port")
                    .font(.system(size: 13, weight: .medium))
                TextField("11434", text: $ollamaPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .font(.system(.callout, design: .monospaced))
                    .onChange(of: ollamaPort) { _, _ in scheduleStatusCheck() }

                if ollamaHost != "127.0.0.1" || ollamaPort != "11434" {
                    Button("Reset") { ollamaHost = "127.0.0.1"; ollamaPort = "11434" }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.bottom, 6)
            Text(endpointPrivacyNotice)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 16)

            // Status row
            HStack(spacing: 10) {
                statusIcon
                statusLabel
                Spacer()
                Button("Check again") { scheduleStatusCheck(immediate: true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Checks the configured Ollama endpoint now")
            }
            .padding(.bottom, 14)

            // Diagnostics button
            Button {
                showDiagnostics = true
            } label: {
                Label("Run Diagnostics", systemImage: "stethoscope")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.bottom, 22)

            Divider()
                .padding(.bottom, 16)

            // System prompt editor
            HStack(alignment: .firstTextBaseline) {
                Text("System Prompt")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Reset to Default") { systemPrompt = kDefaultSystemPrompt }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .disabled(systemPrompt == kDefaultSystemPrompt)
            }
            .padding(.bottom, 6)

            TextEditor(text: $systemPrompt)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .frame(height: 140)
                .padding(.bottom, 16)

            // Done
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
        .task { scheduleStatusCheck(immediate: true) }
        .onDisappear { statusTask?.cancel() }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(endpoint: endpoint, selectedModel: selectedModel)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .checking:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notRunning, .noModel:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .invalidEndpoint:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .checking:
            Text("Checking…").foregroundStyle(.secondary).font(.subheadline)
        case .ready:
            Text("Ollama is running and models are available").foregroundStyle(.green).font(.subheadline)
        case .notRunning:
            Text("Ollama is not running — complete step 2 above").foregroundStyle(.orange).font(.subheadline)
        case .noModel:
            Text("Ollama is running but no models are available — complete step 3").foregroundStyle(.orange).font(.subheadline)
        case .invalidEndpoint:
            Text("Invalid host or port — check the connection settings").foregroundStyle(.orange).font(.subheadline)
        }
    }

    private func scheduleStatusCheck(immediate: Bool = false) {
        // Hosted XCTest launches the app's Settings scene even when no setup
        // UI is under test. Keep that lifecycle deterministic and offline.
        guard PromptMAXXRuntime.automaticNetworkingAllowed else { return }
        statusTask?.cancel()
        let requestID = UUID()
        statusRequestID = requestID
        statusTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await checkStatus(requestID: requestID)
            if statusRequestID == requestID {
                statusTask = nil
            }
        }
    }

    private func checkStatus(requestID: UUID) async {
        guard requestID == statusRequestID else { return }
        status = .checking
        guard let endpoint else {
            guard requestID == statusRequestID else { return }
            status = .invalidEndpoint
            return
        }
        do {
            let client = try OllamaClient(endpoint: endpoint, timeout: 4)
            let models = try await client.fetchModels()
            guard !Task.isCancelled, requestID == statusRequestID else { return }
            status = models.isEmpty ? .noModel : .ready
        } catch {
            guard !Task.isCancelled, requestID == statusRequestID else { return }
            status = .notRunning
        }
    }
}

// MARK: - Setup Step

struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String
    let commands: [String]
    var footnote: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.purple, in: Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(commands, id: \.self) { cmd in
                    CommandBlock(command: cmd)
                }

                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Command Block

struct CommandBlock: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                #else
                UIPasteboard.general.string = command
                #endif
                withAnimation(.spring(response: 0.25)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        withAnimation(.spring(response: 0.25)) { copied = false }
                    }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(copied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    let endpoint: OllamaEndpoint?
    let selectedModel: String
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LogEntry] = []
    @State private var running = false

    struct LogEntry: Identifiable {
        let id = UUID()
        let level: Level
        let message: String
        let timestamp = Date()

        enum Level { case info, success, warning, error, detail }

        var icon: String {
            switch level {
            case .info:    return "arrow.right.circle"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.circle.fill"
            case .detail:  return "doc.text"
            }
        }

        var color: Color {
            switch level {
            case .info:    return .secondary
            case .success: return .green
            case .warning: return .orange
            case .error:   return .red
            case .detail:  return .purple
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundStyle(.purple)
                Text("Diagnostics")
                    .font(.title3.bold())
                Spacer()
                if running {
                    ProgressView().controlSize(.small)
                }
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: entry.icon)
                                    .foregroundStyle(entry.color)
                                    .font(.system(size: 12))
                                    .frame(width: 16)
                                    .padding(.top, 1)
                                Text(entry.message)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(entry.level == .detail ? .secondary : .primary)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .id(entry.id)
                        }

                        if entries.isEmpty && !running {
                            Text("Press Run to start diagnostics")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                    }
                    .padding()
                }
                .onChange(of: entries.count) { _, _ in
                    if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)

            Divider()

            HStack {
                Button(running ? "Running…" : "Run Diagnostics") {
                    Task { await runDiagnostics() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)

                if !entries.isEmpty && !running {
                    Button("Clear") { entries = [] }
                        .buttonStyle(.bordered)
                }

                Spacer()

                Text(endpoint?.baseURL.absoluteString ?? "Invalid endpoint")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .task { await runDiagnostics() }
    }

    private func log(_ level: LogEntry.Level, _ message: String) {
        entries.append(LogEntry(level: level, message: message))
        print("[PromptMAXX Diagnostics] [\(level)] \(message)")
    }

    private func runDiagnostics() async {
        guard !running else { return }
        entries = []
        running = true

        log(.info, "Target: \(endpoint?.baseURL.absoluteString ?? "Invalid endpoint")")
        log(.info, "─────────────────────────────────────")

        guard let endpoint else {
            log(.error, "Invalid host or port. Update the connection settings and try again.")
            running = false
            return
        }
        log(.success, "Endpoint is valid: \(endpoint.baseURL.absoluteString)")

        let client: OllamaClient
        do {
            client = try OllamaClient(endpoint: endpoint, timeout: 8)
        } catch {
            log(.error, "Could not create the Ollama client: \(error.localizedDescription)")
            running = false
            return
        }

        log(.info, "① Fetching available models…")
        let models: [OllamaModel]
        do {
            models = try await client.fetchModels()
            log(.success, "Found \(models.count) model(s)")
            for model in models {
                let size = model.size.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "size unknown"
                let family = model.details?.family ?? "family unknown"
                log(.detail, "  • \(model.model) (\(family), \(size))")
            }
        } catch {
            log(.error, "Could not fetch models: \(error.localizedDescription)")
            running = false
            return
        }

        guard models.contains(where: { $0.model == selectedModel }) else {
            log(.warning, "Selected model \"\(selectedModel)\" is not available. Choose an installed model in the editor.")
            running = false
            return
        }

        log(.info, "② Probing \(selectedModel) generation…")
        let request = OllamaGenerateRequest(model: selectedModel, prompt: "Reply with just the word OK.")
        var response = ""
        do {
            for try await chunk in client.generate(request) {
                if let token = chunk.response { response += token }
                if chunk.done == true { break }
            }
            let summary = response.trimmingCharacters(in: .whitespacesAndNewlines)
            log(.success, "Model responded: \"\(summary.prefix(80))\"")
        } catch {
            log(.error, "Generation failed: \(error.localizedDescription)")
        }

        log(.info, "─────────────────────────────────────")
        log(.info, "Done.")
        running = false
    }
}

#Preview {
    ContentView()
}
