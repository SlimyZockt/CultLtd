#!/usr/bin/env bash
set -eu

# This script creates an optimized release build.

OUT_DIR="build/release"
mkdir -p "$OUT_DIR"
odin build main_release -out:$OUT_DIR/game_release.bin -define:PLATFORM=1 -strict-style -vet -no-bounds-check -o:speed
cp -R assets $OUT_DIR
echo "Release build created in $OUT_DIR"

