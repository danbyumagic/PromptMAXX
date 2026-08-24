#!/usr/bin/env bash

# Reproducible, unsigned local verification for PromptMAXX.
#
# The script deliberately keeps every Xcode invocation in its own DerivedData
# directory and never enables provisioning or signing. CI can point
# PROMPTMAXX_VERIFY_ROOT at $RUNNER_TEMP so logs survive as an artifact.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_INPUT="${PROMPTMAXX_PROJECT:-PromptMAXX.xcodeproj}"
SCHEME="${PROMPTMAXX_SCHEME:-PromptMAXX}"
SDK="${PROMPTMAXX_SDK:-macosx}"
DESTINATION="${PROMPTMAXX_DESTINATION:-platform=macOS}"
VERIFY_ROOT_INPUT="${PROMPTMAXX_VERIFY_ROOT:-}"
ARTIFACTS_INPUT="${PROMPTMAXX_VERIFY_ARTIFACTS:-}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/verify.sh [options]

Runs repository hygiene checks, the full unsigned test suite, unsigned Debug
and Release builds, and Xcode static analysis. Each run uses isolated
DerivedData and writes step logs to an artifacts directory.

Options (environment variables with the PROMPTMAXX_ prefix are also supported):
  --project PATH             Xcode project (PROMPTMAXX_PROJECT)
  --scheme NAME              Xcode scheme (PROMPTMAXX_SCHEME)
  --sdk NAME                 SDK passed to xcodebuild (PROMPTMAXX_SDK)
  --destination VALUE        Explicit destination (PROMPTMAXX_DESTINATION)
  --derived-data-root PATH   Parent for this run's DerivedData/artifacts
                             (PROMPTMAXX_VERIFY_ROOT)
  --artifacts PATH           Parent for this run's artifacts
                             (PROMPTMAXX_VERIFY_ARTIFACTS)
  --dry-run                  Validate inputs and print the planned commands
  -h, --help                 Show this help

The default destination is platform=macOS. Signing and provisioning remain
disabled for every Xcode action.
USAGE
}

die() {
  printf 'verify: %s\n' "$*" >&2
  exit 1
}

require_value() {
  [[ $# -ge 2 && -n "${2:-}" ]] || die "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      require_value "$1" "${2:-}"
      PROJECT_INPUT="$2"
      shift 2
      ;;
    --scheme)
      require_value "$1" "${2:-}"
      SCHEME="$2"
      shift 2
      ;;
    --sdk)
      require_value "$1" "${2:-}"
      SDK="$2"
      shift 2
      ;;
    --destination)
      require_value "$1" "${2:-}"
      DESTINATION="$2"
      shift 2
      ;;
    --derived-data-root)
      require_value "$1" "${2:-}"
      VERIFY_ROOT_INPUT="$2"
      shift 2
      ;;
    --artifacts)
      require_value "$1" "${2:-}"
      ARTIFACTS_INPUT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

cd "$REPO_ROOT"

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required"
[[ -e "$PROJECT_INPUT" ]] || die "project not found: $PROJECT_INPUT"
[[ -n "$SCHEME" ]] || die "scheme must not be empty"
[[ -n "$SDK" ]] || die "SDK must not be empty"
[[ -n "$DESTINATION" ]] || die "destination must not be empty"

SCHEME_FILE="$PROJECT_INPUT/xcshareddata/xcschemes/$SCHEME.xcscheme"
if [[ -f "$SCHEME_FILE" ]]; then
  grep -q 'key = "PROMPTMAXX_TESTING"' "$SCHEME_FILE" \
    || die "shared scheme must set PROMPTMAXX_TESTING=1 for hosted tests"
  grep -q 'argument = "http://offline.invalid"' "$SCHEME_FILE" \
    || die "shared scheme must use the offline Ollama host for tests"
fi

printf 'PromptMAXX verification plan\n'
printf '  project:     %s\n' "$PROJECT_INPUT"
printf '  scheme:      %s\n' "$SCHEME"
printf '  SDK:         %s\n' "$SDK"
printf '  destination: %s\n' "$DESTINATION"

if [[ "$DRY_RUN" == 1 ]]; then
  printf '  actions:     hygiene, test, Debug build, Release build, analyze\n'
  printf 'Dry run complete.\n'
  exit 0
fi

RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
if [[ -n "$VERIFY_ROOT_INPUT" ]]; then
  mkdir -p "$VERIFY_ROOT_INPUT"
  RUN_ROOT="$VERIFY_ROOT_INPUT/$RUN_ID"
  mkdir -p "$RUN_ROOT"
else
  RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PromptMAXX-verify.XXXXXX")"
fi

DERIVED_DATA="$RUN_ROOT/DerivedData"
if [[ -n "$ARTIFACTS_INPUT" ]]; then
  mkdir -p "$ARTIFACTS_INPUT"
  ARTIFACTS_DIR="$ARTIFACTS_INPUT/$RUN_ID"
else
  ARTIFACTS_DIR="$RUN_ROOT/artifacts"
fi
mkdir -p "$DERIVED_DATA" "$ARTIFACTS_DIR"

printf '  DerivedData: %s\n' "$DERIVED_DATA"
printf '  artifacts:   %s\n' "$ARTIFACTS_DIR"

run_step() {
  local label="$1"
  shift
  local log_file="$ARTIFACTS_DIR/$label.log"
  local status

  printf '\n== %s ==\n' "$label"
  printf 'Command:'
  printf ' %q' "$@"
  printf '\n'

  set +e
  "$@" > >(tee "$log_file") 2>&1
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    printf 'FAILED: %s (log: %s)\n' "$label" "$log_file" >&2
    exit "$status"
  fi
  printf 'PASS: %s (log: %s)\n' "$label" "$log_file"
}

check_text_hygiene() {
  local path
  local failed=0

  git diff --check HEAD

  while IFS= read -r -d '' path; do
    if LC_ALL=C grep -n '[[:blank:]]$' "$path"; then
      printf 'Trailing whitespace: %s\n' "$path" >&2
      failed=1
    fi
    if LC_ALL=C grep -n $'\r$' "$path"; then
      printf 'CRLF line ending: %s\n' "$path" >&2
      failed=1
    fi
  done < <(
    git ls-files -co --exclude-standard -z -- \
      '*.swift' '*.sh' '*.yml' '*.yaml' '*.xcscheme' '*.plist' '*.md' '*.json'
  )

  [[ "$failed" -eq 0 ]] || return 1
}

COMMON_XCODE_ARGS=(
  -project "$PROJECT_INPUT"
  -scheme "$SCHEME"
  -sdk "$SDK"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

run_step hygiene check_text_hygiene
run_step shell-syntax bash -n "$SCRIPT_DIR/verify.sh"
run_step project-list xcodebuild -project "$PROJECT_INPUT" -list
run_step tests xcodebuild "${COMMON_XCODE_ARGS[@]}" -resultBundlePath "$ARTIFACTS_DIR/tests.xcresult" test
run_step debug-build xcodebuild "${COMMON_XCODE_ARGS[@]}" -configuration Debug build
run_step release-build xcodebuild "${COMMON_XCODE_ARGS[@]}" -configuration Release build
run_step analyze xcodebuild "${COMMON_XCODE_ARGS[@]}" -configuration Debug analyze

printf '\nVerification succeeded. Logs and Xcode artifacts are in:\n%s\n' "$RUN_ROOT"
