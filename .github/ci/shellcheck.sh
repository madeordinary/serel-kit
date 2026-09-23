#!/usr/bin/env bash
# Print the path to the pinned linter; downloads stay in the caller's temp dir.
set -euo pipefail
version=0.11.0
if command -v shellcheck >/dev/null 2>&1; then
  installed="$(shellcheck --version | sed -n 's/^version: //p')"
  if [ "$installed" = "$version" ]; then
    command -v shellcheck
    exit 0
  fi
fi

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64|Darwin/aarch64)
    platform=darwin.aarch64
    checksum=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f ;;
  Darwin/x86_64)
    platform=darwin.x86_64
    checksum=c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51 ;;
  Linux/aarch64|Linux/arm64)
    platform=linux.aarch64
    checksum=68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc ;;
  Linux/x86_64)
    platform=linux.x86_64
    checksum=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6 ;;
  *) echo "Install ShellCheck $version on this platform, then retry." >&2; exit 1 ;;
esac

destination="${1:?usage: shellcheck.sh <temporary-directory>}"
archive="$destination/shellcheck.tar.gz"
echo "Downloading ShellCheck $version ($platform), verifying SHA256." >&2
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/koalaman/shellcheck/releases/download/v$version/shellcheck-v$version.$platform.tar.gz" \
  --output "$archive"
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check >/dev/null
tar -xzf "$archive" -C "$destination"
printf '%s/shellcheck-v%s/shellcheck\n' "$destination" "$version"
