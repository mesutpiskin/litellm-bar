#!/usr/bin/env bash
# Usage: update-cask.sh <version> <sha256>
set -euo pipefail
VERSION="$1"; SHA="$2"
CASK="$(cd "$(dirname "$0")/.." && pwd)/Casks/litellm-bar.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
