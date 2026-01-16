#!/usr/bin/env bash
# KZ 16.01.2026.

set -euo pipefail

ensure() {
    if ! command -v "$1" >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "$2"
    fi
}

ensure ffmpeg ffmpeg

read -rp "Enter destination folder (relative to \$HOME): " DEST_REL

DEST_DIR="$HOME/$DEST_REL"
mkdir -p "$DEST_DIR"

echo "Output directory: $DEST_DIR"

DVD_TS=$(find /media/"$USER" -maxdepth 2 -type d -name VIDEO_TS 2>/dev/null | head -n 1)

if [[ -z "$DVD_TS" ]]; then
    echo "No mounted DVD with VIDEO_TS found."
    exit 1
fi

DVD_ROOT=$(dirname "$DVD_TS")
DISC_LABEL=$(basename "$DVD_ROOT")

echo "DVD found at: $DVD_ROOT"
echo "Disc label: $DISC_LABEL"
echo

VTS_NUMBERS=$(
    find "$DVD_TS" -maxdepth 1 -name 'VTS_[0-9][0-9]_*.VOB' |
    sed 's|.*/VTS_\([0-9][0-9]\)_.*|\1|' |
    grep -v '^00$' |
    sort -u
)

if [[ -z "$VTS_NUMBERS" ]]; then
    echo "No VTS title sets found."
    exit 1
fi

for NUM in $VTS_NUMBERS; do
    VTS_PREFIX="VTS_${NUM}"
    OUTPUT="$DEST_DIR/${DISC_LABEL}_title_${NUM}.mkv"

    echo "Ripping title set: $VTS_PREFIX"
    echo "Output: $OUTPUT"

    VOB_LIST=$(ls "$DVD_TS"/"${VTS_PREFIX}"_*.VOB | tr '\n' '|')

    ffmpeg -fflags +genpts \
        -i "concat:$VOB_LIST" \
        -map 0:v -map 0:a -map 0:s? \
        -c copy \
        "$OUTPUT"

    echo "Finished: $OUTPUT"
    echo
done

echo "All titles processed."
