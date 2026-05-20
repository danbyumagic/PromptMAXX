# PromptMAXX

A fast, minimal macOS prompt editor with on-device AI refinement via [Ollama](https://ollama.com).

Type a rough idea, press **Return** — the model rewrites it into a clean, direct AI prompt.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## Features

- **Dual-pane editor** — Original and Refined side by side, saved together in history
- **Press Return to refine** — no buttons, no friction
- **On-device AI** — runs entirely through Ollama, nothing leaves your Mac
- **Editable system prompt** — tune the refinement style to your workflow
- **Model picker** — works with any model installed in Ollama (phi4-mini, llama3, etc.)
- **Prompt history** — sidebar with search, swipe-to-delete, and one-click reload
- **⌘C copies the output**, **⌘↩ opens a fresh editor**, type `clear` + Return to reset
- **⌘,** opens Settings with connection config, system prompt editor, and full diagnostics

## Download

Download the latest release from the [Releases](../../releases) page. Unzip and drag `PromptMAXX.app` to your Applications folder.

> Requires macOS 26 (Tahoe) or later.

## Setup

PromptMAXX uses [Ollama](https://ollama.com) to run models locally.

```bash
# 1. Install Ollama
brew install ollama

# 2. Pull a model (phi4-mini is fast and small at ~2.5 GB)
ollama pull phi4-mini

# 3. Start the server
ollama serve
```

Then open PromptMAXX. The app connects to `127.0.0.1:11434` by default. Press ⌘, to change the host/port or swap models.

## How it works

The system prompt instructs the model to convert casual descriptions into concise, direct AI prompt instructions — stripping personal language and filler:

| You type | Refined output |
|---|---|
| i don't like the sound the piano is making it sounds too electronic | piano sound should not sound electronic |
| make the background more warm and cozy feeling | background warmer, cozier atmosphere |
| the text is kind of hard to read can you fix it | improve text readability |

You can edit the system prompt in Settings (⌘,) to change the refinement style entirely.

## Building from source

Requires Xcode 26 beta or later.

```bash
git clone https://github.com/danbyumagic/PromptMAXX.git
cd PromptMAXX
open PromptMAXX.xcodeproj
```

Build and run with ⌘R. The app sandbox requires **Outgoing Connections (Client)** enabled under Target → Signing & Capabilities → App Sandbox.

## License

MIT
