#!/usr/bin/env bash
set -eu

# This script creates an optimized release build.

OUT_DIR="build/debug"
mkdir -p "$OUT_DIR"
odin build main -out:$OUT_DIR/game_debug.bin -debug
cp ./libsteam_api.so ./steam_appid.txt $OUT_DIR
cp -R assets debug_assets $OUT_DIR
echo "Release build created in $OUT_DIR"

