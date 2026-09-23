#!/usr/bin/env bash
# The same preflight runs locally and in GitHub Actions. See README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-all}"
case "$mode" in
  checks|docs|all) ;;
  *) echo "usage: bash tests/ci.sh [checks|docs|all]" >&2; exit 2 ;;
esac
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

checks() {
  command -v jq >/dev/null || { echo "Install jq before running the checks." >&2; exit 1; }
  # Full history and the release tag also support the upgrade suite when present.
  if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    echo "Checks need full history: run git fetch --unshallow --tags." >&2
    exit 1
  fi
  git rev-parse --verify 'refs/tags/v0.1.0^{commit}' >/dev/null || {
    echo "Missing fixture tag v0.1.0: run git fetch origin --tags." >&2
    exit 1
  }
  shellcheck_bin="$(bash .github/ci/shellcheck.sh "$tmp")"
  printf 'ShellCheck: %s\n' "$shellcheck_bin"
  "$shellcheck_bin" --version
  "$shellcheck_bin" install.sh tests/*.sh .github/ci/*.sh

  # Pin the integration fixture locally too; never silently accept partial tests.
  memory_ref="$(cat .github/ci/memory-ref)"
  memory_source=https://github.com/madeordinary/serel-memory.git
  # A source checkout can be on any branch; only the pinned commit is used.
  for candidate in "${SEREL_MEMORY_REPO:-}" ../memory ../serel-memory; do
    if [ -n "$candidate" ] && git -C "$candidate" cat-file -e "$memory_ref^{commit}" 2>/dev/null; then
      memory_source="$(cd "$candidate" && pwd -P)"
      break
    fi
  done
  SEREL_MEMORY_REPO="$tmp/memory"
  git init --quiet "$SEREL_MEMORY_REPO"
  git -C "$SEREL_MEMORY_REPO" fetch --quiet --depth=1 "$memory_source" "$memory_ref"
  git -C "$SEREL_MEMORY_REPO" checkout --quiet --detach FETCH_HEAD
  [ "$(git -C "$SEREL_MEMORY_REPO" rev-parse HEAD)" = "$memory_ref" ] || {
    echo "Memory fixture checkout did not match $memory_ref." >&2
    exit 1
  }
  export SEREL_MEMORY_REPO
  export SEREL_KIT_ALLOW_PARTIAL=0
  printf 'Memory integration fixture: %s\n' "$memory_ref"
  for suite in tests/check-*.sh tests/smoke-*.sh; do
    printf '\n==> %s\n' "$suite"
    bash "$suite"
  done
}

docs() {
  expected_node="v$(cat .github/ci/node-version)"
  if ! command -v node >/dev/null || [ "$(node --version)" != "$expected_node" ]; then
    echo "Use Node $expected_node (see .github/ci/node-version), then retry." >&2
    exit 1
  fi
  mkdir "$tmp/markdownlint"
  cp .github/ci/package.json .github/ci/package-lock.json "$tmp/markdownlint/"
  npm ci --prefix "$tmp/markdownlint" --include=dev --ignore-scripts --no-audit --no-fund
  node "$tmp/markdownlint/node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs" '**/*.md'
}

case "$mode" in
  checks) checks ;;
  docs) docs ;;
  all) checks; docs ;;
esac
