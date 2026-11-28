#!/bin/sh
# Updates downbeat and its skill, then builds and installs the binary.
# Usage: scripts/install.sh [--no-pull]
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
bin_dir="${DOWNBEAT_BIN_DIR:-$HOME/.local/bin}"
state_dir="${DOWNBEAT_STATE_DIR:-$HOME/.local/share/downbeat}"
skills="${SKILLS_REPO:-$repo/../skills}"

case "${1:-}" in
    "")
        git -C "$repo" pull --ff-only
        if [ -d "$skills/.git" ]; then git -C "$skills" pull --ff-only; fi
        ;;
    --no-pull) ;;
    *) echo "Usage: scripts/install.sh [--no-pull]" >&2; exit 64 ;;
esac

# Hash before building, so a change made during the build shows as out of date.
hash="$("$repo/scripts/source-hash.sh")"
swift build -c release --package-path "$repo"
mkdir -p "$bin_dir" "$state_dir"
install -m 755 "$repo/.build/release/downbeat" "$bin_dir/downbeat"
echo "$hash" > "$state_dir/source-hash"
echo "Installed downbeat $("$bin_dir/downbeat" --version) in $bin_dir"
