#!/bin/bash
# KZ 2024.12.29.
# for Kocsis CD set ape 2 wav splits

command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg is not installed."; exit 1; }
command -v shnsplit >/dev/null 2>&1 || { echo "Error: shnsplit is not installed."; exit 1; }

APE_FILE=${1:-image.ape}
CUE_FILE=${2:-image.cue}

if [ ! -f "$APE_FILE" ]; then
    echo "Error: $APE_FILE not found!"
    exit 1
fi

if [ ! -f "$CUE_FILE" ]; then
    echo "Error: $CUE_FILE not found!"
    exit 1
fi

BASE_NAME=$(basename "$APE_FILE" .ape)

echo "Converting $APE_FILE to $BASE_NAME.wav..."
ffmpeg -i "$APE_FILE" "$BASE_NAME.wav" || { echo "FFmpeg conversion failed"; exit 1; }

echo "Splitting tracks..."
shnsplit -o wav -f "$CUE_FILE" "$BASE_NAME.wav" -t "%n-%t" || { echo "shnsplit failed"; exit 1; }

echo "Cleaning up..."
rm "$CUE_FILE" "$APE_FILE" "$BASE_NAME.wav" "$BASE_NAME.log" "$BASE_NAME.accurip" 2>/dev/null

echo "Done!"
