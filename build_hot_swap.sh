#!/usr/bin/env bash
set -eu

OUT_DIR=build/hot_reload
EXE=game_hot_reload.bin
GAME_PATH=game

MODE=""
STRICT=false
ODIN_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
	run|watch)
		MODE="$1"
		shift
		;;
	strict)
		STRICT=true
		shift
		;;
	--)
		shift
		ODIN_ARGS+=("$@")
		break
		;;
	*)
		ODIN_ARGS+=("$1")
		shift
		;;
	esac
done

STRICT_ARGS=()
if [ "$STRICT" = true ]; then
	STRICT_ARGS=(-strict-style -vet)
fi

mkdir -p $OUT_DIR

# root is a special command of the odin compiler that tells you where the Odin
# compiler is located.
ROOT=$(odin root)

# Figure out which DLL extension to use based on platform. Also copy the Linux
# so libs.
case $(uname) in
"Darwin")
    DLL_EXT=".dylib"
    EXTRA_LINKER_FLAGS="-Wl,-rpath $ROOT/vendor/raylib/macos"
    ;;
*)
    DLL_EXT=".so"
    EXTRA_LINKER_FLAGS="'-Wl,-rpath=\$ORIGIN/linux'"

    # Copy the linux libraries into the project automatically.
    if [ ! -d "$OUT_DIR/linux" ]; then
        mkdir -p $OUT_DIR/linux
        cp -r $ROOT/vendor/raylib/linux/libraylib*.so* $OUT_DIR/linux
    fi
    ;;
esac

build_dll() {
    echo "Building game$DLL_EXT"
    odin build "$GAME_PATH" \
        -extra-linker-flags:"$EXTRA_LINKER_FLAGS" \
        -define:RAYLIB_SHARED=true -define:PLATFORM=1 \
        -build-mode:dll -out:"$OUT_DIR/game_tmp$DLL_EXT" \
        -debug \
        "${STRICT_ARGS[@]}" \
        "${ODIN_ARGS[@]}"
}

# Build the game. Note that the game goes into $OUT_DIR while the exe stays in
# the root folder.
build_dll

# Need to use a temp file on Linux because it first writes an empty `game.so`,
# which the game will load before it is actually fully written.
mv "$OUT_DIR/game_tmp$DLL_EXT" "$OUT_DIR/game$DLL_EXT"

# If the executable is already running, then don't try to build and start it.
# -f is there to make sure we match against full name, including .bin
if pgrep -f "$EXE" > /dev/null; then
    echo "Hot reloading..."
    exit 0
fi

echo "Building $EXE"
odin build ./main_hot_reload -out:"$EXE" -debug "${STRICT_ARGS[@]}" "${ODIN_ARGS[@]}"

if [ "$MODE" = "run" ]; then
    echo "Running $EXE"
    ./$EXE &
fi

trap "pkill -P $$ || true" EXIT

if [ "$MODE" = "watch" ]; then
    echo "Running $EXE"
    ./$EXE &

    while inotifywait -r "$GAME_PATH"/*; do
        if build_dll ; then
            echo "Building game$DLL_EXT"
            mv "$OUT_DIR/game_tmp$DLL_EXT" "$OUT_DIR/game$DLL_EXT"
        else
            echo "Build failed. Keeping previous hot-reload DLL; watching for next change..."
        fi
    done
fi
