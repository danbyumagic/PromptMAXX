//
//  ContentView.swift
//  PromptMAXX
//

import SwiftUI

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

// MARK: - Model

struct PromptEntry: Identifiable, Codable {
    let id: UUID
    var original: String
    var refined: String
    let createdAt: Date

    var displayText: String {
        refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original : refined
    }

    var title: String {
        let firstLine = displayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return "Untitled Prompt" }
        return firstLine.count > 50 ? String(firstLine.prefix(50)) + "…" : firstLine
    }

    var wordCount: Int {
        displayText.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    init(original: String, refined: String) {
        self.id = UUID()
        self.original = original
        self.refined = refined
        self.createdAt = Date()
    }
}

@Observable
final class PromptStore {
    var history: [PromptEntry] = []

    private static let key = "promptHistory"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([PromptEntry].self, from: data)
        else { return }
        history = entries
    }

    func add(original: String, refined: String) {
        history.insert(PromptEntry(original: original, refined: refined), at: 0)
        persist()
    }

    func remove(_ entry: PromptEntry) {
        history.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var store = PromptStore()
    @State private var originalText = ""
    @State private var refinedText = ""
    @State private var selectedID: PromptEntry.ID?
    @State private var copyFeedback = false
    @State private var saveFeedback = false
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var showSetup = false
    @AppStorage("selectedModel") private var selectedModel = "phi4-mini:latest"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaHost") private var ollamaHost = "127.0.0.1"
    @AppStorage("systemPrompt") private var systemPrompt = kDefaultSystemPrompt
    @State private var availableModels: [String] = []

    private var ollamaBase: String { "http://\(ollamaHost):\(ollamaPort)" }

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
        } detail: {
            promptEditor
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var historySidebar: some View {
        if store.history.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 38))
                    .foregroundStyle(.quaternary)
                Text("No History")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Saved prompts appear here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("History")
        } else {
            List(store.history, selection: $selectedID) { entry in
                HistoryRowView(entry: entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation { store.remove(entry) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Load Prompt", systemImage: "arrow.up.doc") {
                            loadEntry(entry)
                        }
                        Button("Copy Refined", systemImage: "doc.on.doc") {
                            copyText(entry.displayText)
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            withAnimation { store.remove(entry) }
                        }
                    }
            }
            .listStyle(.sidebar)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Text("\(store.history.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .onChange(of: selectedID) { _, newID in
                guard let id = newID,
                      let entry = store.history.first(where: { $0.id == id })
                else { return }
                loadEntry(entry)
            }
        }
    }

    // MARK: Editor

    private var promptEditor: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

            VSplitView {
                editorPane(
                    label: "Original",
                    systemImage: "doc.text",
                    text: $originalText,
                    placeholder: "Paste your raw prompt here…",
                    showProgress: false
                )
                .frame(minHeight: 80)

                editorPane(
                    label: "Refined",
                    systemImage: "wand.and.sparkles",
                    text: $refinedText,
                    placeholder: isGenerating ? "" : "Write your refined version here…",
                    showProgress: isGenerating
                )
                .frame(minHeight: 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: originalText) { _, newValue in
                if newValue == "clear\n" {
                    clearEditor()
                } else if newValue.hasSuffix("\n") && !isGenerating {
                    let stripped = String(newValue.dropLast())
                    if !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        originalText = stripped
                        refineWithAI()
                    }
                }
            }

            Divider()
            editorStatusBar
        }
        .background(.background)
        .navigationTitle("PromptMAXX")
        #if os(macOS)
        .navigationSubtitle("AI Prompt Editor")
        #endif
        .task { await fetchModels() }
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
                Button("Setup instructions…") { showSetup = true }
            } else {
                ForEach(availableModels, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        if model == selectedModel {
                            Label(modelShortName(model), systemImage: "checkmark")
                        } else {
                            Text(modelShortName(model))
                        }
                    }
                }
                Divider()
                Button("Refresh list", systemImage: "arrow.clockwise") {
                    Task { await fetchModels() }
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
    }

    private func modelShortName(_ name: String) -> String {
        name.replacingOccurrences(of: ":latest", with: "")
    }

    private func fetchModels() async {
        guard let url = URL(string: "\(ollamaBase)/api/tags") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["models"] as? [[String: Any]] else { return }
            let names = list.compactMap { $0["name"] as? String }.sorted()
            availableModels = names
            if !names.isEmpty && !names.contains(selectedModel) {
                selectedModel = names[0]
            }
        } catch {
            availableModels = []
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Button(action: clearEditor) {
                Label("New", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.return, modifiers: .command)
            .help("New prompt  ⌘↩")

            Spacer()

            // Model picker
            modelPicker

            // AI Refine button
            Button(action: isGenerating ? cancelGeneration : refineWithAI) {
                Label(
                    isGenerating ? "Stop" : "Refine",
                    systemImage: isGenerating ? "stop.circle.fill" : "wand.and.sparkles"
                )
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .tint(isGenerating ? .orange : .purple)
            .disabled(originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating)
            .help("Refine with \(selectedModel) via Ollama")

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
            .disabled(!canSave)
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
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy refined prompt (falls back to original)  ⌘C")

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
                .onDisappear { Task { await fetchModels() } }
        }
    }

    private var editorStatusBar: some View {
        HStack {
            if let id = selectedID,
               let entry = store.history.first(where: { $0.id == id }) {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                    Text("Saved \(entry.createdAt, style: .relative)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isGenerating {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.caption2)
                    Text("Refining…")
                        .font(.caption)
                }
                .foregroundStyle(.purple.opacity(0.8))
                .transition(.opacity)
            } else {
                Text("\(wordCount) words · \(activeText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: isGenerating)
    }

    // MARK: Actions

    private func clearEditor() {
        cancelGeneration()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            originalText = ""
            refinedText = ""
            selectedID = nil
        }
    }

    private func loadEntry(_ entry: PromptEntry) {
        originalText = entry.original
        refinedText = entry.refined
    }

    private func refineWithAI() {
        let source = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        isGenerating = true
        refinedText = ""

        generationTask = Task {
            do {
                let url = URL(string: "\(ollamaBase)/api/generate")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 60

                let body: [String: Any] = [
                    "model": selectedModel,
                    "system": systemPrompt,
                    "prompt": source,
                    "stream": true
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let token = json["response"] as? String,
                          !token.isEmpty else { continue }
                    refinedText += token
                }
            } catch is CancellationError {
                // User tapped Stop — leave refined text as-is
            } catch {
                if refinedText.isEmpty {
                    refinedText = "⚠ Ollama not running — start it with: ollama serve"
                }
            }
            isGenerating = false
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func saveToHistory() {
        guard canSave else { return }
        store.add(original: originalText, refined: refinedText)
        withAnimation(.spring(response: 0.3)) { saveFeedback = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation(.spring(response: 0.3)) { saveFeedback = false }
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
    let entry: PromptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 4) {
                if !entry.refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Image(systemName: "wand.and.sparkles")
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.8))
                }
                Text(entry.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                Text("\(entry.wordCount)w")
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
    @State private var showDiagnostics = false
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaHost") private var ollamaHost = "127.0.0.1"
    @AppStorage("systemPrompt") private var systemPrompt = kDefaultSystemPrompt

    private var ollamaBase: String { "http://\(ollamaHost):\(ollamaPort)" }

    enum OllamaStatus {
        case checking, ready, notRunning, noModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Setup Phi-4 Mini")
                        .font(.title2.bold())
                    Text("Runs entirely on your Mac — no internet or account needed")
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
                    title: "Pull Phi-4 Mini",
                    detail: "Microsoft's 3.8B model (~2.5 GB). Only needed once.",
                    commands: ["ollama pull phi4-mini"]
                )
                SetupStep(
                    number: 3,
                    title: "Start the server",
                    detail: "Runs silently on the port configured below.",
                    commands: ["ollama serve"]
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
                    .onChange(of: ollamaHost) { _, _ in Task { await checkStatus() } }

                Text("Port")
                    .font(.system(size: 13, weight: .medium))
                TextField("11434", text: $ollamaPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .font(.system(.callout, design: .monospaced))
                    .onChange(of: ollamaPort) { _, _ in Task { await checkStatus() } }

                if ollamaHost != "127.0.0.1" || ollamaPort != "11434" {
                    Button("Reset") { ollamaHost = "127.0.0.1"; ollamaPort = "11434" }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.bottom, 6)
            Text("Using 127.0.0.1 (IP) avoids DNS lookups and is more reliable than \"localhost\" in a sandboxed app.")
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
                Button("Check again") { Task { await checkStatus() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        .task { await checkStatus() }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(ollamaBase: ollamaBase)
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
            Text("Ollama is not running — complete step 3 above").foregroundStyle(.orange).font(.subheadline)
        case .noModel:
            Text("Ollama is running but phi4-mini is missing — complete step 2").foregroundStyle(.orange).font(.subheadline)
        }
    }

    private func checkStatus() async {
        status = .checking
        // Step 1: confirm Ollama is reachable at all
        guard let rootURL = URL(string: ollamaBase) else { status = .notRunning; return }
        var rootReq = URLRequest(url: rootURL)
        rootReq.timeoutInterval = 3
        do {
            let (_, resp) = try await URLSession.shared.data(for: rootReq)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { status = .notRunning; return }
        } catch {
            status = .notRunning
            return
        }
        // Step 2: list models
        guard let tagsURL = URL(string: "\(ollamaBase)/api/tags") else { status = .notRunning; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: tagsURL)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { status = .notRunning; return }
            let hasAny = !models.isEmpty
            status = hasAny ? .ready : .noModel
        } catch {
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
    let ollamaBase: String
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

                Text(ollamaBase)
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

        log(.info, "Target: \(ollamaBase)")
        log(.info, "─────────────────────────────────────")

        // Step 1: URL sanity
        log(.info, "① Checking URL construction…")
        guard let rootURL = URL(string: ollamaBase) else {
            log(.error, "Invalid URL — check the port value")
            running = false
            return
        }
        log(.success, "URL is valid: \(rootURL.absoluteString)")

        // Step 2: Ping root
        log(.info, "② Connecting to \(ollamaBase)…")
        var rootReq = URLRequest(url: rootURL)
        rootReq.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: rootReq)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(non-UTF8)"
            log(.success, "HTTP \(code) — \(body.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch let error as NSError {
            log(.error, "Connection failed")
            log(.detail, "Domain : \(error.domain)")
            log(.detail, "Code   : \(error.code)")
            log(.detail, "Reason : \(error.localizedDescription)")
            if error.code == -1003 {
                log(.error, "→ Code -1003 = Hostname not found.")
                log(.error, "  The App Sandbox is blocking network access.")
                log(.error, "  Fix 1: In Xcode → Target → Signing & Capabilities")
                log(.error, "         → App Sandbox → check Outgoing Connections (Client)")
                log(.error, "  Fix 2: Set Host to 127.0.0.1 (not localhost)")
                log(.error, "         to bypass DNS lookups in the sandbox.")
            } else if error.code == -1022 {
                log(.warning, "→ Code -1022 = ATS blocked HTTP.")
                log(.warning, "  Fix: Target → Signing & Capabilities")
                log(.warning, "  → App Sandbox → Outgoing Connections (Client) ✓")
            } else if error.code == -1004 {
                log(.warning, "→ Code -1004 = Connection refused.")
                log(.warning, "  Ollama is not listening on this port.")
                log(.warning, "  Run: ollama serve")
            } else if error.code == -1001 {
                log(.warning, "→ Code -1001 = Timed out after 5s.")
            }
            running = false
            return
        }

        // Step 3: /api/tags
        log(.info, "③ Fetching model list (\(ollamaBase)/api/tags)…")
        guard let tagsURL = URL(string: "\(ollamaBase)/api/tags") else {
            log(.error, "Failed to build /api/tags URL")
            running = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: tagsURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            log(.success, "HTTP \(code)")

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                log(.success, "Found \(models.count) model(s):")
                for m in models {
                    let name   = m["name"]   as? String ?? "?"
                    let size   = m["size"]   as? Int ?? 0
                    let family = (m["details"] as? [String: Any])?["family"] as? String ?? "?"
                    log(.detail, "  • \(name)  (\(family), \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
                }
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "(binary)"
                log(.warning, "Could not parse JSON. Raw: \(raw.prefix(200))")
            }
        } catch let error as NSError {
            log(.error, "Failed: \(error.localizedDescription) (code \(error.code))")
        }

        // Step 4: Quick generate probe (no streaming, just check model responds)
        log(.info, "④ Probing generate endpoint…")
        guard let genURL = URL(string: "\(ollamaBase)/api/generate") else {
            log(.error, "Failed to build /api/generate URL")
            running = false
            return
        }
        var genReq = URLRequest(url: genURL)
        genReq.httpMethod = "POST"
        genReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        genReq.timeoutInterval = 30
        let probe: [String: Any] = ["model": "phi4-mini:latest", "prompt": "Reply with just the word OK.", "stream": false]
        genReq.httpBody = try? JSONSerialization.data(withJSONObject: probe)
        do {
            let (data, response) = try await URLSession.shared.data(for: genReq)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resp = json["response"] as? String {
                    log(.success, "Model responded: \"\(resp.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))\"")
                } else {
                    log(.success, "HTTP 200 (response not parsed)")
                }
            } else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                log(.warning, "HTTP \(code): \(raw.prefix(200))")
            }
        } catch let error as NSError {
            log(.error, "Generate failed: \(error.localizedDescription) (code \(error.code))")
        }

        log(.info, "─────────────────────────────────────")
        log(.info, "Done.")
        running = false
    }
}

#Preview {
    ContentView()
}
