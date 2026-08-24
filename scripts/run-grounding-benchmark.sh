#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_BASE="${TMPDIR:-/tmp}"
BUILD_DIR="$(mktemp -d "$TEMP_BASE/PromptMAXX-benchmark.XXXXXX")"

cleanup() {
  if [[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" && "$BUILD_DIR" == "$TEMP_BASE"/PromptMAXX-benchmark.* ]]; then
    rm -rf -- "$BUILD_DIR"
  fi
}
trap cleanup EXIT

cd "$REPO_ROOT"

SOURCES=(
  PromptMAXX/Networking/ModelProvider.swift
  PromptMAXX/Networking/OllamaDTOs.swift
  PromptMAXX/Networking/OllamaClientError.swift
  PromptMAXX/Networking/OllamaEndpoint.swift
  PromptMAXX/Networking/OllamaClient.swift
  PromptMAXX/Grounding/GroundingModels.swift
  PromptMAXX/Grounding/GroundingRetrieval.swift
  PromptMAXX/Grounding/GroundingBenchmark.swift
  scripts/GroundingBenchmarkCLI.swift
)

xcrun swiftc -parse-as-library -O "${SOURCES[@]}" -o "$BUILD_DIR/grounding-benchmark"
"$BUILD_DIR/grounding-benchmark" "$@"
