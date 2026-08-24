# Contributing

PromptMAXX favors small, inspectable changes that preserve the local-first
boundary and factual evidence model.

## Development expectations

- Keep Swift 5 mode and macOS 26 compatibility.
- Prefer typed `Codable`/`Sendable` values and injected dependencies.
- Keep provider/networking policy out of SwiftUI views.
- Preserve cancellation, stale-run protection, and actionable typed errors.
- Do not add subjective quality scores to comparison/evaluation results.
- Treat non-loopback Ollama endpoints as explicit privacy boundaries.
- Use `apply_patch` for source edits and avoid changing project membership when
  the filesystem-synchronized Xcode group can discover a new file.

## Local verification

Run from the repository root. The commands below match the currently observed
local verification and disable code signing:

```bash
xcodebuild -project PromptMAXX.xcodeproj -scheme PromptMAXX \
  -configuration Debug -sdk macosx26.5 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -project PromptMAXX.xcodeproj -scheme PromptMAXX \
  -configuration Debug -sdk macosx26.5 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test

xcodebuild -project PromptMAXX.xcodeproj -scheme PromptMAXX \
  -configuration Release -sdk macosx26.5 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

git diff --check
```

The GitHub Actions workflow uses an unsigned build and conditionally runs the
test target on `macos-latest`; do not infer that a hosted run passed unless its
workflow result is inspected directly. Live Ollama/model-dependent checks
require a local Ollama setup and are not a hosted benchmark claim.

## Pull request checklist

- [ ] Explain the user-visible behavior and files changed.
- [ ] Add deterministic tests for new domain/networking/evaluation behavior.
- [ ] Check invalid endpoint, provider failure, cancellation, and empty states
      where relevant.
- [ ] Confirm prompt/model data is not accidentally placed in an error field or
      log message.
- [ ] Update README/docs/changelog when product behavior or release status
      changes.
