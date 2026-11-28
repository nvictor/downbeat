#!/bin/sh
# Prints one hash of everything the binary is built from.
set -eu
cd "$(dirname "$0")/.."
{ echo Package.swift; find Sources -type f -name '*.swift'; } | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
done | shasum -a 256 | cut -d ' ' -f 1
