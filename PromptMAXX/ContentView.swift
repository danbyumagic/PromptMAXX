//
//  ContentView.swift
//  PromptMAXX
//

import SwiftUI
import FoundationModels

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

    private var model = SystemLanguageModel.default

    private var modelAvailable: Bool {
        if case .available = model.availability { return true }
        return false
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

            Divider()
            editorStatusBar
        }
        .background(.background)
        .navigationTitle("PromptMAXX")
        #if os(macOS)
        .navigationSubtitle("AI Prompt Editor")
        #endif
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
            .disabled(
                (!modelAvailable && !isGenerating) ||
                (originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating)
            )
            .help(modelAvailable ?
                  "Refine with Apple Intelligence  (on-device)" :
                  "Apple Intelligence not available on this device")

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
            .help("Copy refined prompt (falls back to original)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
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
                let session = LanguageModelSession {
                    "You are a prompt engineering expert. When given an AI prompt, improve it to be clearer, more specific, better structured, and more effective. Return ONLY the improved prompt — no explanations, no preamble, no commentary."
                }
                let stream = session.streamResponse(to: source)
                for try await snapshot in stream {
                    refinedText = snapshot.content
                }
            } catch is CancellationError {
                // User tapped Stop — leave refined text as-is
            } catch {
                refinedText = ""
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

#Preview {
    ContentView()
}
